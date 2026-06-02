from pathlib import Path

from fastapi import FastAPI
from fastapi.staticfiles import StaticFiles

from app.adapters.market.yfinance_source import YFinanceSource
from app.api.routes import dashboard, export, ledger, quotes
from app.core.config import get_settings
from app.db.connection import connect
from app.db.migrations import migrate


def create_app(
    db_path: str | Path | None = None,
    market_data_source=None,
    watchlist_path: str | Path | None = None,
) -> FastAPI:
    settings = get_settings()
    app = FastAPI(title="tese", version="0.1.0")
    app.state.db_path = Path(db_path) if db_path is not None else settings.db_path
    app.state.watchlist_path = (
        Path(watchlist_path) if watchlist_path is not None else settings.watchlist_path
    )
    app.state.market_data_source = market_data_source or YFinanceSource()
    app.state.conn = connect(app.state.db_path)
    migrate(app.state.conn)

    app.include_router(dashboard.router)
    app.include_router(ledger.router)
    app.include_router(export.router)
    app.include_router(quotes.router)

    @app.get("/health")
    def health():
        app.state.conn.execute("SELECT 1").fetchone()
        return {"ok": True, "db_path": str(app.state.db_path)}

    static_dir = Path(__file__).with_name("static")
    app.mount("/", StaticFiles(directory=static_dir, html=True), name="static")
    return app


app = create_app()
