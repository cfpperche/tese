#!/usr/bin/env python3
"""reminders-helper.py — YAML mutation helper for the /remind skill.

Subcommands invoked from the skill body or the readout hook:

  add "<text>" [--due YYYY-MM-DD] [--check '<cmd>'] [--links a,b,c]
  list [--all]                     # default: pending + past-snoozed only
  readout                          # readout hook view (same filter as list)
  done <id-or-position>
  snooze <id-or-position> <Nd|Nw|Nm|YYYY-MM-DD>
  resolve <id-or-position>         # prints the resolved id (for skill body)
  get-check <id-or-position>       # prints the entry's check_command verbatim

Reads/writes $CLAUDE_PROJECT_DIR/.agent0/reminders.yaml (creates with
`reminders: []` if absent). Field order preserved via sort_keys=False.

Exit codes: 0 ok, 2 user error (invalid arg / unknown id), 3 IO error.
Fail-open on missing yaml lib: print stderr advisory, exit 3.
"""

from __future__ import annotations

import argparse
import datetime as dt
import os
import re
import sys
from pathlib import Path

try:
    import yaml
except ImportError:
    sys.stderr.write(
        "reminders-helper: PyYAML missing — pip install pyyaml (or install Go-yq for read-only paths)\n"
    )
    sys.exit(3)


SLUG_MAX_CHARS = 30
SLUG_WORD_COUNT = 5
DURATION_RE = re.compile(r"^([0-9]+)(d|w|m)$")
ISO_DATE_RE = re.compile(r"^[0-9]{4}-[0-9]{2}-[0-9]{2}$")
ID_RE = re.compile(r"^r-[0-9]{4}-[0-9]{2}-[0-9]{2}-[a-z0-9-]+$")


def yaml_path() -> Path:
    root = Path(os.environ.get("CLAUDE_PROJECT_DIR", os.getcwd()))
    return root / ".agent0" / "reminders.yaml"


def load() -> dict:
    p = yaml_path()
    if not p.exists():
        return {"reminders": []}
    with p.open() as f:
        data = yaml.safe_load(f) or {}
    if "reminders" not in data or data["reminders"] is None:
        data["reminders"] = []
    return data


def dump(data: dict) -> None:
    p = yaml_path()
    p.parent.mkdir(parents=True, exist_ok=True)
    with p.open("w") as f:
        yaml.safe_dump(data, f, sort_keys=False, default_flow_style=False, allow_unicode=True)


def today_iso() -> str:
    return dt.date.today().isoformat()


def now_utc_iso() -> str:
    return dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def make_slug(text: str) -> str:
    words = re.findall(r"[a-z0-9]+", text.lower())
    slug = "-".join(words[:SLUG_WORD_COUNT])
    return slug[:SLUG_MAX_CHARS].rstrip("-") or "entry"


def make_id(text: str, when: str | None = None) -> str:
    return f"r-{when or today_iso()}-{make_slug(text)}"


def filtered(data: dict) -> list[dict]:
    """Same view as readout: pending + past-snoozed."""
    today = today_iso()
    out = []
    for e in data["reminders"]:
        st = e.get("status", "pending")
        if st == "pending":
            out.append(e)
        elif st == "snoozed" and e.get("snoozed_until", "") <= today:
            out.append(e)
    return out


def resolve(data: dict, ident: str) -> dict:
    """Resolve <id-or-position> against the filtered list. Position is 1-indexed."""
    if ident.isdigit():
        idx = int(ident)
        view = filtered(data)
        if idx < 1 or idx > len(view):
            die(f"only {len(view)} surfaceable reminder(s); position {idx} out of range")
        return view[idx - 1]
    if not ID_RE.match(ident):
        die(f"identifier must be a positive integer or stable id (r-YYYY-MM-DD-slug); got: {ident}")
    for e in data["reminders"]:
        if e.get("id") == ident:
            return e
    die(f"no reminder with id: {ident}")


def parse_duration(s: str) -> str:
    """Return ISO date for `Nd`/`Nw`/`Nm` or pass-through for `YYYY-MM-DD`."""
    if ISO_DATE_RE.match(s):
        return s
    m = DURATION_RE.match(s)
    if not m:
        die(f"snooze: duration must be Nd|Nw|Nm or YYYY-MM-DD (got: {s})")
    n, unit = int(m.group(1)), m.group(2)
    days = {"d": n, "w": n * 7, "m": n * 30}[unit]
    return (dt.date.today() + dt.timedelta(days=days)).isoformat()


def die(msg: str, code: int = 2) -> None:
    sys.stderr.write(f"reminders-helper: {msg}\n")
    sys.exit(code)


# ---------- subcommands ----------


def cmd_add(args: argparse.Namespace) -> None:
    text = (args.text or "").strip()
    if not text:
        die("add: text is required")
    if "\n" in text:
        die("add: text must be a single line")
    if args.due and not ISO_DATE_RE.match(args.due):
        die(f"add: --due must be strict YYYY-MM-DD (got: {args.due})")
    data = load()
    existing = {e.get("id") for e in data["reminders"]}
    base_id = make_id(text)
    rid, n = base_id, 2
    while rid in existing:
        rid = f"{base_id}-{n}"
        n += 1
    entry: dict = {"id": rid, "created": today_iso(), "context": text, "status": "pending"}
    if args.due:
        entry["due"] = args.due
    if args.check:
        entry["check_command"] = args.check
    if args.links:
        entry["links"] = [l.strip() for l in args.links.split(",") if l.strip()]
    data["reminders"].append(entry)
    dump(data)
    print(f"added: {rid}: {text}")


def cmd_list(args: argparse.Namespace) -> None:
    data = load()
    view = data["reminders"] if args.all else filtered(data)
    if not view:
        print("no pending reminders")
        return
    for i, e in enumerate(view, start=1):
        suffix_bits = []
        if "due" in e:
            suffix_bits.append(f"due: {e['due']}")
        if e.get("status") == "snoozed":
            suffix_bits.append(f"snoozed_until: {e.get('snoozed_until', '?')}")
        if "check_command" in e:
            suffix_bits.append(f"check: {e['check_command']}")
        if "links" in e:
            suffix_bits.append("links: " + ", ".join(e["links"]))
        head = f"{i}. [{e['id']}] {e['context']}"
        print(head)
        for s in suffix_bits:
            print(f"   · {s}")
    print(f"{len(view)} reminder(s)")


def cmd_readout(args: argparse.Namespace) -> None:
    """Same as `list` but exit silently on empty so the hook can pick the wording."""
    data = load()
    view = filtered(data)
    if not view:
        return
    for e in view:
        print(f"- [{e['id']}] {e['context']}")
        if "due" in e:
            print(f"  · due: {e['due']}")
        if e.get("status") == "snoozed":
            print(f"  · snoozed_until: {e.get('snoozed_until', '?')}")
        if "check_command" in e:
            print(f"  · check_command: {e['check_command']}")
        if "links" in e:
            print(f"  · links: " + ", ".join(e["links"]))


def cmd_done(args: argparse.Namespace) -> None:
    data = load()
    e = resolve(data, args.ident)
    e["status"] = "done"
    e["completed_ts"] = now_utc_iso()
    dump(data)
    print(f"done: {e['id']}: {e['context']}")


def cmd_snooze(args: argparse.Namespace) -> None:
    snoozed_until = parse_duration(args.duration)
    data = load()
    e = resolve(data, args.ident)
    e["status"] = "snoozed"
    e["snoozed_until"] = snoozed_until
    dump(data)
    print(f"snoozed: {e['id']} until {snoozed_until}")


def cmd_resolve(args: argparse.Namespace) -> None:
    data = load()
    e = resolve(data, args.ident)
    print(e["id"])


def cmd_get_check(args: argparse.Namespace) -> None:
    data = load()
    e = resolve(data, args.ident)
    if "check_command" not in e:
        die(f"check: entry {e['id']} has no check_command")
    sys.stdout.write(e["check_command"])


# ---------- arg parsing ----------


def main() -> None:
    p = argparse.ArgumentParser(prog="reminders-helper", description=__doc__)
    sub = p.add_subparsers(dest="cmd", required=True)

    p_add = sub.add_parser("add")
    p_add.add_argument("text")
    p_add.add_argument("--due")
    p_add.add_argument("--check")
    p_add.add_argument("--links")
    p_add.set_defaults(func=cmd_add)

    p_list = sub.add_parser("list")
    p_list.add_argument("--all", action="store_true", help="include done + future-snoozed")
    p_list.set_defaults(func=cmd_list)

    p_readout = sub.add_parser("readout")
    p_readout.set_defaults(func=cmd_readout)

    p_done = sub.add_parser("done")
    p_done.add_argument("ident")
    p_done.set_defaults(func=cmd_done)

    p_snooze = sub.add_parser("snooze")
    p_snooze.add_argument("ident")
    p_snooze.add_argument("duration")
    p_snooze.set_defaults(func=cmd_snooze)

    p_resolve = sub.add_parser("resolve")
    p_resolve.add_argument("ident")
    p_resolve.set_defaults(func=cmd_resolve)

    p_check = sub.add_parser("get-check")
    p_check.add_argument("ident")
    p_check.set_defaults(func=cmd_get_check)

    args = p.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
