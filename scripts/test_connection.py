"""
Quick check that Python can talk to Snowflake.
Run:  python scripts/test_connection.py
"""

from sf_connection import get_connection

conn = get_connection()
try:
    cur = conn.cursor()
    cur.execute("SELECT CURRENT_USER(), CURRENT_ROLE(), CURRENT_WAREHOUSE(), CURRENT_DATABASE(), CURRENT_VERSION()")
    user, role, wh, db, version = cur.fetchone()
    print("Connected to Snowflake!")
    print(f"  user      : {user}")
    print(f"  role      : {role}")
    print(f"  warehouse : {wh}")
    print(f"  database  : {db}")
    print(f"  version   : {version}")
finally:
    conn.close()
