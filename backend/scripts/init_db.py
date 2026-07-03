"""Create the PostGIS extension and all tables. Idempotent.

Usage: python -m scripts.init_db  (from backend/, with .venv active)
"""

from sqlalchemy import text

from app.db import Base, engine
from app import models  # noqa: F401 — registers tables on Base


def main() -> None:
    with engine.connect() as conn:
        conn.execute(text("CREATE EXTENSION IF NOT EXISTS postgis"))
        conn.commit()
    Base.metadata.create_all(engine)
    print("Database initialized: PostGIS extension + tables created.")


if __name__ == "__main__":
    main()
