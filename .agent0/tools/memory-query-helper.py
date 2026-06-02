#!/usr/bin/env python3
"""memory-query-helper.py — search / list / confirm / decay / backfill for .agent0/memory/.

Reads/writes entry frontmatter (per the memory frontmatter schema) and
projects via .agent0/memory.config.json. Mirrors the reminders-helper.py
pattern: bash dispatcher delegates to this Python helper for
YAML mutation + filtering.

Subcommands:
  backfill-metadata <file>   one-shot: populate created_at/last_accessed/confirmed_count
  search <pattern>           case-insensitive grep across entries
  list [--type=T] [--stale=Nd|Nw|Nm]
  confirm <name1> [<name2> ...]
  decay [--readout]          staleness readout (framed when --readout)

Defaults (overridable in .agent0/memory.config.json):
  cap.max_line_chars: 250
  decay.threshold_days: 60
  decay.confirm_boost_days: 14

Exit codes: 0 ok, 2 user error (unknown name / invalid arg), 3 IO / dep error.
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import re
import subprocess
import sys
from pathlib import Path

try:
    import yaml
except ImportError:
    sys.stderr.write("memory-query-helper: PyYAML missing — pip install pyyaml\n")
    sys.exit(3)


# ---------- paths + constants ----------


def project_root() -> Path:
    return Path(os.environ.get("AGENT0_PROJECT_DIR") or os.environ.get("CLAUDE_PROJECT_DIR", os.getcwd()))


def memory_dir() -> Path:
    return project_root() / ".agent0" / "memory"


def config_path() -> Path:
    return project_root() / ".agent0" / "memory.config.json"


DEFAULTS = {
    "cap": {"max_line_chars": 250},
    "decay": {"threshold_days": 60, "confirm_boost_days": 14},
}

DURATION_RE = re.compile(r"^([0-9]+)(d|w|m)$")


# ---------- config + frontmatter parsing ----------


def load_config() -> dict:
    p = config_path()
    if not p.exists():
        return DEFAULTS
    try:
        raw = json.loads(p.read_text())
    except (json.JSONDecodeError, OSError) as e:
        sys.stderr.write(
            f"memory-config-advisory: {p.name} unparseable ({e.__class__.__name__}); using defaults\n"
        )
        return DEFAULTS
    cap_max = raw.get("cap", {}).get("max_line_chars", DEFAULTS["cap"]["max_line_chars"])
    threshold = raw.get("decay", {}).get("threshold_days", DEFAULTS["decay"]["threshold_days"])
    boost = raw.get("decay", {}).get("confirm_boost_days", DEFAULTS["decay"]["confirm_boost_days"])
    return {
        "cap": {"max_line_chars": int(cap_max)},
        "decay": {"threshold_days": int(threshold), "confirm_boost_days": int(boost)},
    }


def parse_frontmatter(text: str) -> tuple[dict | None, str]:
    """Return (frontmatter_dict, body) for a markdown file. None FM if absent/malformed."""
    if not text.startswith("---\n"):
        return None, text
    end = text.find("\n---\n", 4)
    if end == -1:
        return None, text
    block = text[4:end]
    body = text[end + 5 :]
    try:
        return yaml.safe_load(block) or {}, body
    except yaml.YAMLError:
        return None, text


def dump_frontmatter(fm: dict, body: str) -> str:
    head = yaml.safe_dump(fm, sort_keys=False, default_flow_style=False, allow_unicode=True)
    return f"---\n{head}---\n{body}"


def iter_entries():
    """Yield (path, frontmatter, body) for each .agent0/memory/*.md except MEMORY.md."""
    md = memory_dir()
    if not md.is_dir():
        return
    for p in sorted(md.glob("*.md")):
        if p.name == "MEMORY.md":
            continue
        text = p.read_text()
        fm, body = parse_frontmatter(text)
        yield p, fm, body


def find_entry_by_name(name: str) -> Path | None:
    """Resolve <name> to entry path: try basename match first (preferred slug), then name field."""
    md = memory_dir()
    p = md / f"{name}.md"
    if p.exists():
        return p
    for path, fm, _ in iter_entries():
        if fm and fm.get("name") == name:
            return path
    return None


# ---------- date / duration helpers ----------


def today() -> dt.date:
    return dt.date.today()


def today_iso() -> str:
    return today().isoformat()


def parse_iso_date(s: str) -> dt.date | None:
    """Accepts 'YYYY-MM-DD' or 'YYYY-MM-DDTHH:MM:SS[Z|+offset]'. None on failure."""
    if not s:
        return None
    try:
        if "T" in s:
            return dt.datetime.fromisoformat(s.replace("Z", "+00:00")).date()
        return dt.date.fromisoformat(s)
    except (ValueError, TypeError):
        return None


def parse_duration_to_days(s: str) -> int:
    m = DURATION_RE.match(s)
    if not m:
        die(f"duration must be Nd|Nw|Nm (got: {s})")
    n, unit = int(m.group(1)), m.group(2)
    return {"d": n, "w": n * 7, "m": n * 30}[unit]


def die(msg: str, code: int = 2) -> None:
    sys.stderr.write(f"memory-query-helper: {msg}\n")
    sys.exit(code)


# ---------- staleness ----------


def staleness_score(fm: dict, boost_days: int) -> int:
    meta = (fm or {}).get("metadata", {}) or {}
    last = parse_iso_date(meta.get("last_accessed", "")) or parse_iso_date(
        meta.get("created_at", "")
    )
    if last is None:
        # No signal — treat as fresh (today), not stale
        last = today()
    age = (today() - last).days
    confirmed = int(meta.get("confirmed_count", 0) or 0)
    return age - confirmed * boost_days


# ---------- subcommands ----------


def cmd_backfill_metadata(args: argparse.Namespace) -> None:
    p = Path(args.file)
    if not p.exists():
        die(f"backfill-metadata: file not found: {p}")
    text = p.read_text()
    fm, body = parse_frontmatter(text)
    if fm is None:
        die(f"backfill-metadata: {p.name} has no parseable frontmatter")
    meta = fm.setdefault("metadata", {})
    has_all = all(k in meta for k in ("created_at", "last_accessed", "confirmed_count"))
    if has_all:
        return  # idempotent no-op

    if "created_at" not in meta:
        try:
            r = subprocess.run(
                ["git", "log", "--follow", "--format=%aI", "--", str(p)],
                capture_output=True,
                text=True,
                check=False,
                cwd=project_root(),
            )
            lines = [ln for ln in r.stdout.strip().splitlines() if ln.strip()]
            meta["created_at"] = lines[-1] if lines else f"{today_iso()}T00:00:00Z"
        except (subprocess.SubprocessError, OSError):
            meta["created_at"] = f"{today_iso()}T00:00:00Z"

    meta.setdefault("last_accessed", today_iso())
    meta.setdefault("confirmed_count", 0)

    p.write_text(dump_frontmatter(fm, body))
    print(f"backfilled: {p.stem}")


def cmd_search(args: argparse.Namespace) -> None:
    pattern = re.compile(re.escape(args.pattern), re.IGNORECASE)
    hits = 0
    for p, _fm, _body in iter_entries():
        text = p.read_text()
        for line in text.splitlines():
            if pattern.search(line):
                print(f"{p.relative_to(project_root())}: {line.strip()}")
                hits += 1
                break
    if hits == 0:
        print("(no matches)")


def cmd_list(args: argparse.Namespace) -> None:
    cfg = load_config()
    stale_days = parse_duration_to_days(args.stale) if args.stale else None
    out = []
    for p, fm, _ in iter_entries():
        if fm is None:
            continue
        meta = fm.get("metadata", {}) or {}
        if args.type and meta.get("type") != args.type:
            continue
        if stale_days is not None:
            last = parse_iso_date(meta.get("last_accessed", "")) or parse_iso_date(
                meta.get("created_at", "")
            )
            if last and (today() - last).days < stale_days:
                continue
        name = fm.get("name", p.stem)
        desc = fm.get("description", "")
        out.append(f"{name} — {desc}")
    if not out:
        print("(no matches)")
        return
    for line in out:
        print(line)


def cmd_confirm(args: argparse.Namespace) -> None:
    today_str = today_iso()
    for name in args.names:
        p = find_entry_by_name(name)
        if p is None:
            die(f"confirm: no entry matching '{name}' (looked up basename {name}.md and name: field)")
        text = p.read_text()
        fm, body = parse_frontmatter(text)
        if fm is None:
            die(f"confirm: {p.name} has no parseable frontmatter")
        meta = fm.setdefault("metadata", {})
        meta["last_accessed"] = today_str
        meta["confirmed_count"] = int(meta.get("confirmed_count", 0) or 0) + 1
        p.write_text(dump_frontmatter(fm, body))
        print(f"confirmed: {p.stem} (last_accessed={today_str}, count={meta['confirmed_count']})")


def cmd_project_entries(args: argparse.Namespace) -> None:
    """Emit one line per entry: <slug>\\t<name>\\t<description>. Used by memory-project.sh.

    Resolves folded/multi-line YAML descriptions correctly (single-line on stdout).
    Newlines inside descriptions are collapsed to spaces; tabs are replaced with spaces.
    """
    for p, fm, _ in iter_entries():
        if fm is None:
            continue
        name = fm.get("name", p.stem)
        desc = fm.get("description", "") or ""
        desc = " ".join(desc.split())  # collapse any whitespace runs
        name = " ".join(str(name).split())
        if not desc:
            continue
        # tab is the field separator; escape any literal tabs in the values
        name = name.replace("\t", " ")
        desc = desc.replace("\t", " ")
        print(f"{p.stem}\t{name}\t{desc}")


def cmd_decay(args: argparse.Namespace) -> None:
    cfg = load_config()
    threshold = cfg["decay"]["threshold_days"]
    boost = cfg["decay"]["confirm_boost_days"]
    stale = []
    for p, fm, _ in iter_entries():
        score = staleness_score(fm, boost)
        if score > threshold:
            meta = (fm or {}).get("metadata", {}) or {}
            stale.append(
                {
                    "name": (fm or {}).get("name", p.stem),
                    "slug": p.stem,
                    "score": score,
                    "confirmed": int(meta.get("confirmed_count", 0) or 0),
                }
            )

    if args.readout:
        print("=== MEMORY DECAY ===")
        if not stale:
            print("(no stale entries)")
        else:
            for e in stale:
                print(f"- {e['slug']} — stale {e['score']}d, confirmed {e['confirmed']}x")
            print(
                f"run bash .agent0/tools/memory-query.sh list --stale={threshold}d to inspect"
            )
        print("=== end MEMORY DECAY ===")
    else:
        if not stale:
            print("(no stale entries)")
            return
        for e in stale:
            print(f"{e['slug']}: stale {e['score']}d, confirmed {e['confirmed']}x")


# ---------- arg parsing ----------


def main() -> None:
    p = argparse.ArgumentParser(prog="memory-query-helper", description=__doc__)
    sub = p.add_subparsers(dest="cmd", required=True)

    p_bf = sub.add_parser("backfill-metadata")
    p_bf.add_argument("file")
    p_bf.set_defaults(func=cmd_backfill_metadata)

    p_search = sub.add_parser("search")
    p_search.add_argument("pattern")
    p_search.set_defaults(func=cmd_search)

    p_list = sub.add_parser("list")
    p_list.add_argument("--type", default=None)
    p_list.add_argument("--stale", default=None)
    p_list.set_defaults(func=cmd_list)

    p_confirm = sub.add_parser("confirm")
    p_confirm.add_argument("names", nargs="+")
    p_confirm.set_defaults(func=cmd_confirm)

    p_decay = sub.add_parser("decay")
    p_decay.add_argument("--readout", action="store_true")
    p_decay.set_defaults(func=cmd_decay)

    p_proj = sub.add_parser("project-entries")
    p_proj.set_defaults(func=cmd_project_entries)

    args = p.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
