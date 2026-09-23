import json, sqlite3, os

# Paths
PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
JSON_PATH = os.path.join(PROJECT_ROOT, 'news_sources_ar.json')
DB_PATH = os.path.join(PROJECT_ROOT, 'assets', 'news_base_source.db')

# Ensure assets directory exists
os.makedirs(os.path.dirname(DB_PATH), exist_ok=True)

# Load JSON data
with open(JSON_PATH, 'r', encoding='utf-8') as f:
    data = json.load(f)

# Create SQLite DB
conn = sqlite3.connect(DB_PATH)
cur = conn.cursor()
cur.execute('''
CREATE TABLE IF NOT EXISTS news (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    url TEXT,
    title TEXT,
    category TEXT,
    html TEXT
)''')

# Insert rows
for item in data.get('countries', []):
    # Each country has 'sources' list
    for src in item.get('sources', []):
        cur.execute(
            'INSERT INTO news (url, title, category, html) VALUES (?, ?, ?, ?)',
            (src.get('url'), src.get('title'), src.get('category'), src.get('html'))
        )

conn.commit()
conn.close()
print(f'SQLite DB generated at {DB_PATH}')
