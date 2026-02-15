"""Database connection and initialization."""

from sqlmodel import SQLModel, Session, create_engine

from server.config import settings

# Import all models so SQLModel registers them
import server.models  # noqa: F401

engine = create_engine(
    f"sqlite:///{settings.db_path}",
    echo=settings.debug,
    connect_args={"check_same_thread": False},
)


def init_db() -> None:
    """Create all tables and enable WAL mode."""
    SQLModel.metadata.create_all(engine)

    # Enable WAL mode for better concurrent read performance
    with engine.connect() as conn:
        conn.exec_driver_sql("PRAGMA journal_mode=WAL")
        conn.exec_driver_sql("PRAGMA synchronous=NORMAL")
        conn.exec_driver_sql("PRAGMA foreign_keys=ON")
        conn.commit()


def get_session():
    """FastAPI dependency: yields a database session."""
    with Session(engine) as session:
        yield session
