import json
import sqlite3
import os

# Paths (adjust if needed)
BASE_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
JSON_PATH = os.path.join(BASE_DIR, 'news_sources_ar.json')
DB_PATH = os.path.join(BASE_DIR, 'assets', 'news_base_source.db')

# Load JSON data
with open(JSON_PATH, 'r', encoding='utf-8') as f:
    data = json.load(f)

# Ensure assets directory exists
os.makedirs(os.path.dirname(DB_PATH), exist_ok=True)

# Connect to SQLite (will create if not exists)
conn = sqlite3.connect(DB_PATH)
cur = conn.cursor()

# Drop table if exists
cur.execute('DROP TABLE IF EXISTS sources')

# Create table
cur.execute('''
CREATE TABLE sources (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    country TEXT,
    country_code TEXT,
    name TEXT,
    url TEXT,
    category TEXT,
    type TEXT,
    language TEXT,
    rank INTEGER
)''')

# Insert rows flattening country hierarchy
for country_entry in data.get('countries', []):
    country = country_entry.get('country')
    country_code = country_entry.get('country_code')
    for src in country_entry.get('sources', []):
        cur.execute('''
        INSERT INTO sources (country, country_code, name, url, category, type, language, rank)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)''', (
            country,
            country_code,
            src.get('name'),
            src.get('url'),
            src.get('category'),
            src.get('type'),
            ','.join(src.get('language', [])),
            src.get('rank')
        ))

conn.commit()
conn.close()
print(f"SQLite DB generated at {DB_PATH}")
