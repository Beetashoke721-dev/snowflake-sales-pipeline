"""
Generate fake (but realistic-looking) e-commerce data for the pipeline.

It simulates a small online shop called "ShopEasy" and writes CSV files to ./data:
    customers.csv        - 200 customers (with a few messy / duplicate rows)
    products.csv         - 30 products
    orders_batch_1.csv   - orders for 1-7 Nov 2026 (the "first day" of our pipeline)
    orders_batch_2.csv   - NEW orders for 8-10 Nov + STATUS UPDATES to old orders

The data is deliberately a little dirty (extra spaces, wrong casing, duplicates,
negative quantities, bad dates) so the cleaning step in Snowflake has real work to do.

Only uses the Python standard library - no extra installs needed.
Run:  python data_generator/generate_data.py
"""

import csv
import random
from datetime import date, timedelta
from pathlib import Path

random.seed(42)  # same "random" data every time, so results are repeatable

DATA_DIR = Path(__file__).resolve().parent.parent / "data"
DATA_DIR.mkdir(exist_ok=True)

FIRST_NAMES = ["Aarav", "Diya", "Rohan", "Ananya", "Kabir", "Isha", "Arjun", "Meera",
               "Vihaan", "Sara", "Aditya", "Priya", "Rahul", "Neha", "Karan", "Pooja",
               "John", "Emma", "Liam", "Olivia"]
LAST_NAMES = ["Sharma", "Verma", "Gupta", "Chakraborty", "Iyer", "Reddy", "Das", "Mehta",
              "Nair", "Singh", "Patel", "Bose", "Smith", "Brown"]
CITIES = ["Kolkata", "Mumbai", "Delhi", "Bengaluru", "Chennai", "Hyderabad", "Pune", "Jaipur"]

PRODUCTS = [
    ("Electronics", ["Wireless Mouse", "Bluetooth Speaker", "USB-C Cable", "Power Bank",
                     "Earbuds", "Keyboard", "Webcam", "Smart Watch"]),
    ("Home", ["Coffee Mug", "Table Lamp", "Cushion Cover", "Wall Clock", "Water Bottle",
              "Storage Box", "Bedsheet"]),
    ("Books", ["Python Basics", "SQL for Beginners", "Data Engineering 101",
               "Cloud Computing Guide", "Statistics Made Easy"]),
    ("Fashion", ["T-Shirt", "Jeans", "Sneakers", "Backpack", "Sunglasses", "Cap",
                 "Wallet", "Hoodie", "Watch Strap", "Socks Pack"]),
]

STATUSES = ["placed", "shipped", "delivered", "cancelled"]


def messy(text: str) -> str:
    """Randomly make a string messy: extra spaces or odd casing (~15% of the time)."""
    r = random.random()
    if r < 0.05:
        return f"  {text}  "
    if r < 0.10:
        return text.upper()
    if r < 0.15:
        return text.lower()
    return text


def write_csv(filename: str, header: list, rows: list) -> None:
    path = DATA_DIR / filename
    with open(path, "w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerow(header)
        writer.writerows(rows)
    print(f"  wrote {len(rows):>5} rows -> {path.relative_to(DATA_DIR.parent)}")


def make_customers(n: int = 200) -> list:
    rows = []
    start = date(2025, 1, 1)
    for cid in range(1, n + 1):
        first = random.choice(FIRST_NAMES)
        last = random.choice(LAST_NAMES)
        email = f"{first}.{last}{cid}@example.com"
        signup = start + timedelta(days=random.randint(0, 600))
        rows.append([cid, messy(first), messy(last), messy(email),
                     messy(random.choice(CITIES)), signup.isoformat()])
    # dirty data: duplicate a few customers (same id appears twice)
    rows += random.sample(rows, 5)
    return rows


def make_products() -> list:
    rows = []
    pid = 1
    for category, names in PRODUCTS:
        for name in names:
            price = round(random.uniform(99, 4999), 2)
            rows.append([pid, name, category, price])
            pid += 1
    return rows


def make_orders(start_id: int, count: int, first_day: date, days: int,
                n_customers: int, n_products: int) -> list:
    rows = []
    for oid in range(start_id, start_id + count):
        order_day = first_day + timedelta(days=random.randint(0, days - 1))
        rows.append([
            oid,
            random.randint(1, n_customers),
            random.randint(1, n_products),
            random.randint(1, 5),
            order_day.isoformat(),
            messy(random.choices(STATUSES, weights=[50, 25, 20, 5])[0]),
        ])
    return rows


def add_dirty_orders(rows: list) -> list:
    """Inject some bad rows so we can practise data cleaning."""
    rows = rows + random.sample(rows, 10)            # exact duplicates
    for row in random.sample(rows, 5):              # negative / zero quantity
        row[3] = random.choice([0, -1, -3])
    for row in random.sample(rows, 3):              # unreadable dates
        row[4] = "not-a-date"
    random.shuffle(rows)
    return rows


def main() -> None:
    print("Generating ShopEasy sample data...")
    customers = make_customers()
    products = make_products()
    n_customers, n_products = 200, len(products)

    # Batch 1: 1,000 orders between 1 and 7 Nov 2026
    batch1 = make_orders(1, 1000, date(2026, 11, 1), 7, n_customers, n_products)

    # Batch 2: 500 new orders between 8 and 10 Nov 2026 ...
    batch2 = make_orders(1001, 500, date(2026, 11, 8), 3, n_customers, n_products)
    # ... plus status updates for 100 old orders (placed -> shipped/delivered).
    # These test that our MERGE *updates* existing rows instead of duplicating them.
    for old in random.sample(batch1, 100):
        updated = list(old)
        updated[5] = random.choice(["shipped", "delivered"])
        batch2.append(updated)

    header_orders = ["order_id", "customer_id", "product_id", "quantity", "order_date", "status"]
    write_csv("customers.csv",
              ["customer_id", "first_name", "last_name", "email", "city", "signup_date"],
              customers)
    write_csv("products.csv", ["product_id", "product_name", "category", "unit_price"], products)
    write_csv("orders_batch_1.csv", header_orders, add_dirty_orders(batch1))
    write_csv("orders_batch_2.csv", header_orders, add_dirty_orders(batch2))
    print("Done!")


if __name__ == "__main__":
    main()
