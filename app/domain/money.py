from decimal import ROUND_HALF_UP, Decimal
from typing import Any

TWOPLACES = Decimal("0.01")


def dec(value: Any) -> Decimal:
    if isinstance(value, Decimal):
        return value
    if value is None:
        return Decimal("0")
    return Decimal(str(value))


def q2(value: Any) -> Decimal:
    return dec(value).quantize(TWOPLACES, rounding=ROUND_HALF_UP)


def money(value: Any) -> str:
    return f"{q2(value):.2f}"


def qty_text(value: Any) -> str:
    value = dec(value).normalize()
    return format(value, "f")
