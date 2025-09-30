import os
import json
import asyncio
import random
from contextlib import asynccontextmanager
from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.responses import HTMLResponse
import psycopg2
import psycopg2.extras
from kafka import KafkaConsumer
import threading
import math
import uvicorn

# --- Database Configuration ---
DB_HOST = os.getenv("DB_HOST", "localhost")
DB_PORT = os.getenv("DB_PORT", "5432")
DB_NAME = os.getenv("DB_NAME", "workshop")
DB_USER = os.getenv("DB_USER", "workshop")
DB_PASSWORD = os.getenv("DB_PASSWORD", "workshop")

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

def get_db_connection():
    """Establishes a connection to the PostgreSQL database."""
    return psycopg2.connect(host=DB_HOST, port=DB_PORT, dbname=DB_NAME, user=DB_USER, password=DB_PASSWORD)

# --- API Endpoints ---
@app.get("/api/cats")
def get_cats(status: str = "available", page: int = 1, limit: int = 6):
    if status not in ['available', 'adopted']:
        return {"error": "Invalid status"}, 400
    with get_db_connection() as conn:
        with conn.cursor(cursor_factory=psycopg2.extras.DictCursor) as cursor:
            cursor.execute("SELECT COUNT(*) FROM cats WHERE status = %s", (status,))
            total_records = cursor.fetchone()[0]
            total_pages = math.ceil(total_records / limit)
            offset = (page - 1) * limit
            cursor.execute("SELECT * FROM cats WHERE status = %s ORDER BY admitted_date DESC LIMIT %s OFFSET %s", (status, limit, offset))
            cats_data = [dict(row) for row in cursor.fetchall()]
    return {"cats": cats_data, "total": total_records, "page": page, "totalPages": total_pages}

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
    """
    Consumes from Kafka, enriches alerts, simulates adoptions, and broadcasts to WebSockets.
    """
    consumer = KafkaConsumer(
        *ALERT_TOPICS,
        bootstrap_servers=KAFKA_BOOTSTRAP_SERVERS,
        value_deserializer=lambda m: json.loads(m.decode('utf-8')),
        auto_offset_reset='latest'
    )
    print("Kafka consumer thread started...")
    for message in consumer:
        payload_data = message.value
        
        if message.topic == 'cat-health-alerts':
            # ... existing health alert enrichment ...
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
            # **MODIFIED**: Enrich with visitor name
            visitor_id = payload_data.get('visitor_id')
            visitor_name = "A visitor" # Default value
            if visitor_id:
                try:
                    with get_db_connection() as conn:
                        with conn.cursor() as cursor:
                            cursor.execute("SELECT name FROM visitors WHERE visitor_id = %s", (visitor_id,))
                            result = cursor.fetchone()
                            # Use just the first name for a cleaner message
                            if result: visitor_name = result[0].split()[0]
                except Exception as e:
                    print(f"Database lookup failed for visitor_id {visitor_id}: {e}")
            
            # Add visitor name and update the alert message before sending
            payload_data['visitor_name'] = visitor_name
            payload_data['alert_message'] = f"Potential adopter detected: {visitor_name} has liked {payload_data.get('number_of_likes')} cats."
            
            alert_payload = json.dumps({"type": "potential_adopter", "data": payload_data})
            manager.broadcast(alert_payload)
            
            # Closed-Loop Adoption Logic
            if random.random() < 0.25:
                liked_cats_str = payload_data.get('liked_cats', '')
                if liked_cats_str:
                    liked_cats_list = [cat.strip() for cat in liked_cats_str.split(',')]
                    cat_to_adopt_id = random.choice(liked_cats_list)
                    try:
                        with get_db_connection() as conn:
                            with conn.cursor() as cursor:
                                cursor.execute("SELECT status, name FROM cats WHERE cat_id = %s FOR UPDATE", (cat_to_adopt_id,))
                                result = cursor.fetchone()
                                if result and result[0] == 'available':
                                    cat_name_to_adopt = result[1]
                                    cursor.execute("UPDATE cats SET status = 'adopted', adopted_date = NOW() WHERE cat_id = %s", (cat_to_adopt_id,))
                                    conn.commit()
                                    print(f"SUCCESS: {cat_name_to_adopt} ({cat_to_adopt_id}) has been adopted!")
                                    
                                    # **MODIFIED**: Broadcast the enriched status update with the cat's name
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

# --- Serve Frontend ---
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
