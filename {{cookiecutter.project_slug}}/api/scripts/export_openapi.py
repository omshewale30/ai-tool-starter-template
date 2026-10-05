#!/usr/bin/env python3
"""Print the API's OpenAPI document as JSON.

The frontend generates its typed client from this (`npm run generate:api` in
web/). Run from anywhere; it needs the API's dependencies installed.
"""
from __future__ import annotations

import json
import os
import sys
from pathlib import Path

# Import-time settings validation needs a safe local configuration; nothing here
# touches a database or Azure.
os.environ.setdefault("ENVIRONMENT", "test")
os.environ.setdefault("AUTH_MODE", "disabled")
os.environ.setdefault("AI_PROVIDER", "mock")
os.environ.setdefault("DATABASE_URL", "sqlite+pysqlite:///:memory:")

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from app.main import app  # noqa: E402

if __name__ == "__main__":
    print(json.dumps(app.openapi(), indent=2, sort_keys=True))
