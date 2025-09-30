
import psycopg2

endpoint = "localhost:5432"
username = "workshop"
password = "workshop"

def create_cats_table(cursor):
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS cats (
            cat_id VARCHAR(50) PRIMARY KEY,
            name VARCHAR(50) NOT NULL,
            coat_color VARCHAR(50),
            coat_length VARCHAR(50),
            age INT,
            archetype VARCHAR(50) NOT NULL,
            status VARCHAR(20) NOT NULL,
            admitted_date TIMESTAMP NOT NULL,
            adopted_date TIMESTAMP,
            last_checkup_time TIMESTAMP
        )
    """)

def create_visitors_table(cursor):
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS visitors (
            visitor_id VARCHAR(50) PRIMARY KEY,
            name VARCHAR(50) NOT NULL,
            archetype VARCHAR(50) NOT NULL,
            first_visit_date TIMESTAMP NOT NULL
        )
    """)

def create_tables():
    conn = psycopg2.connect(
        host=endpoint,
        database="workshop",
        user=username,
        password=password
    )
    cursor = conn.cursor()
    
    create_cats_table(cursor)
    create_visitors_table(cursor)
    
    conn.commit()
    cursor.close()
    conn.close()


"""
1. read from data/cats.csv file
2. write data from the csv file to the cats table
3. 
"""