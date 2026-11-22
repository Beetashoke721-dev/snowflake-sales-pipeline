"""
Run one or more .sql files against Snowflake, statement by statement,
and print a small preview of each result.

    python scripts/run_sql.py sql/02_raw_layer.sql
    python scripts/run_sql.py sql/03_load_raw.sql sql/04_staging.sql

(You can also just paste the same files into a Snowsight worksheet - both work.)
"""

import sys
from pathlib import Path

from sf_connection import get_connection

PREVIEW_ROWS = 5


def first_line(sql: str) -> str:
    line = " ".join(sql.split())
    return line[:90] + ("..." if len(line) > 90 else "")


def main() -> None:
    files = sys.argv[1:]
    if not files:
        sys.exit("Usage: python scripts/run_sql.py <file.sql> [more.sql ...]")

    conn = get_connection()
    try:
        for file in files:
            sql_text = Path(file).read_text(encoding="utf-8")
            print(f"\n=== Running {file} ===")
            for cur in conn.execute_string(sql_text, remove_comments=True):
                print(f"\n> {first_line(cur.query)}")
                if cur.description:
                    cols = [c[0] for c in cur.description]
                    rows = cur.fetchmany(PREVIEW_ROWS)
                    print("  " + " | ".join(cols))
                    for row in rows:
                        print("  " + " | ".join(str(v) for v in row))
        print("\nAll done.")
    finally:
        conn.close()


if __name__ == "__main__":
    main()
