import os
import json
import asyncio
import random
from contextlib import asynccontextmanager
from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.responses import HTMLResponse
from fastapi.staticfiles import StaticFiles
import psycopg
from psycopg.rows import dict_row
import threading
import math
import uvicorn
from kafka import KafkaConsumer


# --- Database Configuration ---
DB_HOST = os.getenv("DB_HOST", "localhost")
DB_PORT = os.getenv("DB_PORT", "5432")
DB_NAME = os.getenv("DB_NAME", "workshop")
DB_USER = os.getenv("DB_USER", "workshop")
DB_PASSWORD = os.getenv("DB_PASSWORD", "workshop")
CONN_STRING = f"dbname='{DB_NAME}' user='{DB_USER}' host='{DB_HOST}' port='{DB_PORT}' password='{DB_PASSWORD}'"

# --- Kafka Configuration ---
KAFKA_BOOTSTRAP_SERVERS = os.getenv('KAFKA_BROKERS', 'localhost:9092')
ALERT_TOPICS = ['potential-adopters', 'cat-health-alerts']

# --- Lifespan Event Handler ---
@asynccontextmanager
async def lifespan(app: FastAPI):
    manager.loop = asyncio.get_running_loop()
    print("Application startup: Starting Kafka consumer...")
    kafka_thread = threading.Thread(target=consume_kafka_alerts, daemon=True)
    kafka_thread.start()
    yield
    print("Application shutdown.")

# --- FastAPI Application ---
app = FastAPI(lifespan=lifespan)

# --- Mount Static Files ---
app.mount("/static/cats", StaticFiles(directory="images"), name="cat_images")

def get_db_connection():
    """Establishes a connection to the PostgreSQL database using psycopg3."""
    return psycopg.connect(CONN_STRING)

# --- API Endpoints ---
@app.get("/api/cats")
def get_cats(status: str = "available", page: int = 1, limit: int = 6):
    if status not in ['available', 'adopted']:
        return {"error": "Invalid status"}, 400
    with get_db_connection() as conn:
        with conn.cursor(row_factory=dict_row) as cursor:
            cursor.execute("SELECT COUNT(*) FROM cats WHERE status = %s", (status,))
            total_records = cursor.fetchone()['count']
            total_pages = math.ceil(total_records / limit)
            offset = (page - 1) * limit
            cursor.execute("SELECT * FROM cats WHERE status = %s ORDER BY admitted_date DESC LIMIT %s OFFSET %s", (status, limit, offset))
            cats_data = cursor.fetchall()
    return {"cats": cats_data, "total": total_records, "page": page, "totalPages": total_pages}

@app.get("/api/cat-images")
def get_cat_images():
    """Returns a list of available cat image filenames."""
    image_dir = "images"
    try:
        if not os.path.isdir(image_dir):
            print(f"Image directory not found at {image_dir}")
            return {"images": []}
        files = [f for f in os.listdir(image_dir) if f.endswith('.png')]
        return {"images": files}
    except Exception as e:
        print(f"Error reading image directory: {e}")
        return {"images": []}

# --- WebSocket Handling ---
class ConnectionManager:
    def __init__(self):
        self.active_connections: list[WebSocket] = []
        self.loop: asyncio.AbstractEventLoop = None

    async def connect(self, websocket: WebSocket):
        await websocket.accept()
        self.active_connections.append(websocket)

    def disconnect(self, websocket: WebSocket):
        self.active_connections.remove(websocket)

    def broadcast(self, message: str):
        if self.loop:
            asyncio.run_coroutine_threadsafe(self._broadcast(message), self.loop)
        else:
            print("Error: Event loop not set. Cannot broadcast message.")

    async def _broadcast(self, message: str):
        for connection in self.active_connections:
            await connection.send_text(message)

manager = ConnectionManager()

def consume_kafka_alerts():
    consumer = KafkaConsumer(
        *ALERT_TOPICS,
        bootstrap_servers=KAFKA_BOOTSTRAP_SERVERS,
        value_deserializer=lambda m: json.loads(m.decode('utf-8')) if m is not None else {},
        auto_offset_reset='latest'
    )
    print("Kafka consumer thread started...")
    for message in consumer:
        payload_data = message.value

        if not payload_data:
            continue

        if message.topic == 'cat-health-alerts':
            cat_id = payload_data.get('cat_id')
            cat_name = "Unknown Cat"
            if cat_id:
                try:
                    with get_db_connection() as conn:
                        with conn.cursor() as cursor:
                            cursor.execute("SELECT name FROM cats WHERE cat_id = %s", (cat_id,))
                            result = cursor.fetchone()
                            if result: cat_name = result[0]
                except Exception as e:
                    print(f"Database lookup failed for cat_id {cat_id}: {e}")
            payload_data['cat_name'] = cat_name
            payload = json.dumps({"type": "cat_health_alert", "data": payload_data})
            manager.broadcast(payload)

        elif message.topic == 'potential-adopters':
            visitor_id = payload_data.get('visitor_id')
            visitor_name = "A visitor"
            if visitor_id:
                try:
                    with get_db_connection() as conn:
                        with conn.cursor() as cursor:
                            cursor.execute("SELECT name FROM visitors WHERE visitor_id = %s", (visitor_id,))
                            result = cursor.fetchone()
                            if result: visitor_name = result[0].split()[0]
                except Exception as e:
                    print(f"Database lookup failed for visitor_id {visitor_id}: {e}")

            payload_data['visitor_name'] = visitor_name
            payload_data['alert_message'] = f"Potential adopter detected: {visitor_name} has liked {payload_data.get('number_of_likes')} cats."
            alert_payload = json.dumps({"type": "potential_adopter", "data": payload_data})
            manager.broadcast(alert_payload)

            if random.random() < 0.25:
                liked_cats_str = payload_data.get('liked_cats', '')
                if liked_cats_str:
                    liked_cats_list = [cat.strip() for cat in liked_cats_str.split(',')]
                    cat_to_adopt_id = random.choice(liked_cats_list)
                    try:
                        with get_db_connection() as conn:
                            with conn.cursor(row_factory=dict_row) as cursor:
                                cursor.execute("SELECT status, name FROM cats WHERE cat_id = %s FOR UPDATE", (cat_to_adopt_id,))
                                result = cursor.fetchone()
                                if result and result['status'] == 'available':
                                    cat_name_to_adopt = result['name']
                                    cursor.execute("UPDATE cats SET status = 'adopted', adopted_date = NOW() WHERE cat_id = %s", (cat_to_adopt_id,))
                                    conn.commit()
                                    print(f"SUCCESS: {cat_name_to_adopt} ({cat_to_adopt_id}) has been adopted!")

                                    update_payload = json.dumps({
                                        "type": "cat_status_update",
                                        "data": {"cat_id": cat_to_adopt_id, "cat_name": cat_name_to_adopt, "status": "adopted"}
                                    })
                                    manager.broadcast(update_payload)
                    except Exception as e:
                        print(f"Error during adoption process: {e}")

@app.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket):
    await manager.connect(websocket)
    try:
        while True:
            await websocket.receive_text()
    except WebSocketDisconnect:
        manager.disconnect(websocket)
        print("Client disconnected")

@app.get("/", response_class=HTMLResponse)
async def read_root():
    try:
        with open("dashboard.html") as f:
            return HTMLResponse(content=f.read(), status_code=200)
    except FileNotFoundError:
        return HTMLResponse(content="<h1>Dashboard file not found</h1>", status_code=404)

if __name__ == "__main__":
    port = int(os.environ.get("PORT", 8088))
    uvicorn.run("main:app", host="0.0.0.0", port=port, reload=True)
