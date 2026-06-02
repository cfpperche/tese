import argparse
from pathlib import Path

from app.adapters.portfolio.manual_holdings import import_holdings_yaml
from app.core.config import get_settings
from app.db.connection import connect
from app.db.migrations import migrate
from app.db.repositories import LedgerRepository
from app.domain.export import write_tax_year_export


def main() -> None:
    parser = argparse.ArgumentParser(prog="tese")
    subparsers = parser.add_subparsers(dest="command", required=True)
    export = subparsers.add_parser("export")
    export.add_argument("--tax-year", type=int, required=True)
    export.add_argument("--db", type=Path, default=None)
    export.add_argument("--out", type=Path, default=Path("exports"))
    import_holdings = subparsers.add_parser("import-holdings")
    import_holdings.add_argument("--file", type=Path, default=Path("holdings.yaml"))
    import_holdings.add_argument("--db", type=Path, default=None)
    args = parser.parse_args()

    settings = get_settings()
    conn = connect(args.db or settings.db_path)
    migrate(conn)
    try:
        if args.command == "export":
            target = write_tax_year_export(conn, args.tax_year, args.out)
            print(target)
        elif args.command == "import-holdings":
            import_holdings_yaml(LedgerRepository(conn), args.file)
            print(args.file)
    finally:
        conn.close()


if __name__ == "__main__":
    main()
