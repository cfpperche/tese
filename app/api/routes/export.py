from fastapi import APIRouter, Request, Response

from app.domain.export import generate_tax_year_export

router = APIRouter(prefix="/api/export", tags=["export"])


@router.get("/{tax_year}/summary")
def export_summary(tax_year: int, request: Request):
    return generate_tax_year_export(request.app.state.conn, tax_year).summary


@router.get("/{tax_year}/events.csv")
def export_events_csv(tax_year: int, request: Request):
    package = generate_tax_year_export(request.app.state.conn, tax_year)
    return Response(package.events_csv, media_type="text/csv")
