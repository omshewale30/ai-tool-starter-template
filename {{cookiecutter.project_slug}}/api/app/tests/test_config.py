"""Settings parsing and validation."""
from app.core.config import Settings


def test_plain_postgres_urls_use_the_psycopg_driver():
    for url in ("postgres://u:p@h:5432/db", "postgresql://u:p@h:5432/db"):
        settings = Settings(environment="test", database_url=url)
        assert settings.database_url == "postgresql+psycopg://u:p@h:5432/db"


def test_other_database_urls_are_unchanged():
    url = "sqlite+pysqlite:///:memory:"
    assert Settings(environment="test", database_url=url).database_url == url
