"""
One place that knows how to connect to Snowflake.

Reads your settings from the .env file (never commit that file!).
Supports two login methods:
  1. Key-pair  (recommended - works on every account)  -> set SNOWFLAKE_PRIVATE_KEY_PATH
  2. Password  (only for trial accounts)                -> set SNOWFLAKE_PASSWORD
"""

import os
import sys

import snowflake.connector
from dotenv import load_dotenv

load_dotenv()  # loads variables from .env into the environment


def get_connection():
    required = ["SNOWFLAKE_ACCOUNT", "SNOWFLAKE_USER"]
    missing = [v for v in required if not os.getenv(v)]
    if missing:
        sys.exit(f"Missing settings in .env: {', '.join(missing)}  (copy .env.example to .env)")

    params = {
        "account": os.getenv("SNOWFLAKE_ACCOUNT"),
        "user": os.getenv("SNOWFLAKE_USER"),
        "role": os.getenv("SNOWFLAKE_ROLE", "PIPELINE_ROLE"),
        "warehouse": os.getenv("SNOWFLAKE_WAREHOUSE", "PIPELINE_WH"),
        "database": os.getenv("SNOWFLAKE_DATABASE", "SALES_DB"),
    }

    key_path = os.getenv("SNOWFLAKE_PRIVATE_KEY_PATH")
    password = os.getenv("SNOWFLAKE_PASSWORD")

    if key_path:
        params["private_key_file"] = key_path
        if os.getenv("SNOWFLAKE_PRIVATE_KEY_PASSPHRASE"):
            params["private_key_file_pwd"] = os.getenv("SNOWFLAKE_PRIVATE_KEY_PASSPHRASE")
    elif password:
        params["password"] = password
    else:
        sys.exit("Set either SNOWFLAKE_PRIVATE_KEY_PATH or SNOWFLAKE_PASSWORD in .env")

    return snowflake.connector.connect(**params)
