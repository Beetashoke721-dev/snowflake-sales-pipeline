"""
Upload CSV files from your laptop into the Snowflake internal stage
(@SALES_DB.RAW.LANDING_STAGE) using the PUT command.

    python scripts/upload_files.py --batch 1   # customers, products, orders_batch_1
    python scripts/upload_files.py --batch 2   # orders_batch_2 (new + updated orders)

Files land in sub-folders of the stage:  customers/  products/  orders/
"""

import argparse
from pathlib import Path

from sf_connection import get_connection

DATA_DIR = Path(__file__).resolve().parent.parent / "data"
STAGE = "@SALES_DB.RAW.LANDING_STAGE"

BATCHES = {
    "1": [("customers.csv", "customers"),
          ("products.csv", "products"),
          ("orders_batch_1.csv", "orders")],
    "2": [("orders_batch_2.csv", "orders")],
}


def main() -> None:
    parser = argparse.ArgumentParser(description="Upload CSV files to the Snowflake stage")
    parser.add_argument("--batch", choices=BATCHES.keys(), required=True)
    args = parser.parse_args()

    conn = get_connection()
    try:
        cur = conn.cursor()
        for filename, folder in BATCHES[args.batch]:
            path = DATA_DIR / filename
            if not path.exists():
                raise SystemExit(f"{path} not found - run data_generator/generate_data.py first")
            # as_posix() gives forward slashes, which PUT needs even on Windows
            sql = f"PUT 'file://{path.as_posix()}' {STAGE}/{folder}/ AUTO_COMPRESS=TRUE OVERWRITE=TRUE"
            cur.execute(sql)
            source, target, *_rest, status, _msg = cur.fetchone()
            print(f"  {source:<22} -> {STAGE}/{folder}/{target}  [{status}]")
        print("Upload finished. Check it in Snowflake with:  LIST @SALES_DB.RAW.LANDING_STAGE;")
    finally:
        conn.close()


if __name__ == "__main__":
    main()
