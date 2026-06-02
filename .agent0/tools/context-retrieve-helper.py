#!/usr/bin/env python3
"""Deterministic lexical retrieval for Agent0 context sources.

This helper intentionally uses only Python's standard library. It is not a
semantic RAG engine: it ranks project-local source pointers and leaves the
source files canonical.
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import re
import sys
import unicodedata
from dataclasses import asdict, dataclass
from pathlib import Path


SOURCE_ORDER = {"rule": 0, "memory": 1, "spec": 2, "handoff": 3}
DEFAULT_CORPUS = ("rules", "memory", "specs", "handoff")
WORD_RE = re.compile(r"[a-z0-9][a-z0-9_-]{1,}", re.IGNORECASE)


@dataclass
class Candidate:
    source_class: str
    authority: str
    path: str
    title: str
    anchor: str
    score: int
    reason: str
    freshness: str
    read_before_acting: str
    snippet: str


def project_root() -> Path:
    return Path(os.environ.get("AGENT0_PROJECT_DIR") or os.environ.get("CLAUDE_PROJECT_DIR", os.getcwd()))


def rel(path: Path) -> str:
    try:
        return path.relative_to(project_root()).as_posix()
    except ValueError:
        return path.as_posix()


def normalize(value: str) -> str:
    value = unicodedata.normalize("NFKD", value)
    value = "".join(ch for ch in value if not unicodedata.combining(ch))
    return value.lower()


def tokens(value: str) -> list[str]:
    seen: set[str] = set()
    out: list[str] = []
    for tok in WORD_RE.findall(normalize(value)):
        if len(tok) < 3 or tok in seen:
            continue
        seen.add(tok)
        out.append(tok)
    return out


def first_heading(text: str, fallback: str) -> str:
    for line in text.splitlines():
        if line.startswith("# "):
            return line[2:].strip()
    return fallback


def strip_frontmatter(text: str) -> str:
    if not text.startswith("---\n"):
        return text
    end = text.find("\n---\n", 4)
    if end == -1:
        return text
    return text[end + 5 :]


def compact(value: str, limit: int = 180) -> str:
    one = " ".join(value.split())
    if len(one) <= limit:
        return one
    return one[: limit - 3].rstrip() + "..."


def frontmatter_value(text: str, key: str) -> str:
    if not text.startswith("---\n"):
        return ""
    end = text.find("\n---\n", 4)
    if end == -1:
        return ""
    block = text[4:end]
    match = re.search(rf"^[ \t]*{re.escape(key)}:[ \t]*['\"]?([^'\"\n]+)", block, re.MULTILINE)
    return match.group(1).strip() if match else ""


def memory_freshness(entry_path: Path) -> str:
    if not entry_path.exists():
        return "memory-entry-missing"
    text = entry_path.read_text(errors="replace")
    last = frontmatter_value(text, "last_accessed") or frontmatter_value(text, "created_at")
    confirmed = frontmatter_value(text, "confirmed_count") or "0"
    if not last:
        return "unknown"
    date_part = last.split("T", 1)[0]
    try:
        age = (dt.date.today() - dt.date.fromisoformat(date_part)).days
    except ValueError:
        return f"metadata-unparseable:{date_part}"
    return f"last_accessed={date_part}; age_days={age}; confirmed_count={confirmed}"


def score(query: str, title: str, path: str, text: str) -> tuple[int, str]:
    q_norm = normalize(query).strip()
    title_norm = normalize(title)
    path_norm = normalize(path)
    text_norm = normalize(text)
    q_tokens = tokens(query)
    if not q_tokens:
        return 0, "no-query-tokens"

    total = 0
    hits: list[str] = []
    if q_norm and len(q_norm) >= 4 and q_norm in text_norm:
        total += 14
        hits.append("phrase")
    for tok in q_tokens:
        token_score = 0
        if tok in title_norm:
            token_score += 8
        if tok in path_norm:
            token_score += 5
        if tok in text_norm:
            token_score += 2
        if token_score:
            total += token_score
            hits.append(tok)
    if total == 0:
        return 0, "no lexical match"
    return total, "lexical: " + ", ".join(hits[:8])


def rule_candidates(query: str) -> list[Candidate]:
    root = project_root()
    rules_dir = root / ".agent0" / "context" / "rules"
    out: list[Candidate] = []
    if not rules_dir.is_dir():
        return out
    for path in sorted(rules_dir.glob("*.md")):
        text = path.read_text(errors="replace")
        body = strip_frontmatter(text)
        title = first_heading(body, path.stem)
        relpath = rel(path)
        s, reason = score(query, title, relpath, text)
        if s <= 0:
            continue
        out.append(
            Candidate(
                source_class="rule",
                authority="authoritative-capsule",
                path=relpath,
                title=title,
                anchor=f"# {title}",
                score=s,
                reason=reason,
                freshness="live-file",
                read_before_acting="Read this rule before acting when the task depends on this Agent0 capacity.",
                snippet=compact(body),
            )
        )
    return out


MEMORY_LINE_RE = re.compile(r"^- \[([^\]]+)\]\(([^)]+)\)\s+[—-]\s+(.*)$")


def memory_candidates(query: str) -> list[Candidate]:
    root = project_root()
    index = root / ".agent0" / "memory" / "MEMORY.md"
    out: list[Candidate] = []
    if not index.exists():
        return out
    for line in index.read_text(errors="replace").splitlines():
        match = MEMORY_LINE_RE.match(line.strip())
        if not match:
            continue
        name, link, desc = match.groups()
        entry = root / ".agent0" / "memory" / link
        relpath = rel(entry)
        haystack = f"{name}\n{link}\n{desc}"
        s, reason = score(query, name, relpath, haystack)
        if s <= 0:
            continue
        out.append(
            Candidate(
                source_class="memory",
                authority="evidence-pointer",
                path=relpath,
                title=name,
                anchor=name,
                score=s,
                reason=reason + "; adapter=MEMORY.md",
                freshness=memory_freshness(entry),
                read_before_acting="Read the memory entry before acting; this snippet is non-authoritative evidence.",
                snippet=compact(desc),
            )
        )
    return out


def section(text: str, heading: str) -> str:
    lines = text.splitlines()
    capture = False
    out: list[str] = []
    for line in lines:
        if line == f"## {heading}":
            capture = True
            continue
        if capture and line.startswith("## "):
            break
        if capture:
            out.append(line)
    return "\n".join(out).strip()


def spec_candidates(query: str) -> list[Candidate]:
    root = project_root()
    specs = root / "docs" / "specs"
    out: list[Candidate] = []
    if not specs.is_dir():
        return out
    for spec in sorted(specs.glob("[0-9][0-9][0-9]-*/spec.md")):
        text = spec.read_text(errors="replace")
        title = first_heading(text, spec.parent.name)
        intent = section(text, "Intent")
        open_questions = section(text, "Open questions")
        status = ""
        for line in text.splitlines():
            if line.startswith("**Status:**"):
                status = line
                break
        relpath = rel(spec)
        haystack = "\n".join([title, status, intent, open_questions, relpath])
        s, reason = score(query, title, relpath, haystack)
        if s <= 0:
            continue
        out.append(
            Candidate(
                source_class="spec",
                authority="evidence-pointer",
                path=relpath,
                title=title,
                anchor="## Intent",
                score=s,
                reason=reason,
                freshness="live-file",
                read_before_acting="Read the spec before acting; this snippet is non-authoritative evidence.",
                snippet=compact(intent or status or title),
            )
        )
    return out


def handoff_candidates(query: str) -> list[Candidate]:
    root = project_root()
    path = root / ".agent0" / "HANDOFF.md"
    out: list[Candidate] = []
    if not path.exists():
        return out
    text = path.read_text(errors="replace")
    for heading in ("Current State", "Active Work", "Next Actions", "Decisions & Gotchas"):
        body = section(text, heading)
        if not body:
            continue
        title = f"Session handoff — {heading}"
        relpath = rel(path)
        s, reason = score(query, title, relpath, f"{title}\n{body}")
        if s <= 0:
            continue
        out.append(
            Candidate(
                source_class="handoff",
                authority="evidence-pointer",
                path=relpath,
                title=title,
                anchor=f"## {heading}",
                score=s,
                reason=reason,
                freshness="live-file",
                read_before_acting="Read the handoff section before acting; this snippet is non-authoritative evidence.",
                snippet=compact(body),
            )
        )
    return out


def collect(query: str, corpus: set[str]) -> list[Candidate]:
    out: list[Candidate] = []
    if "rules" in corpus:
        out.extend(rule_candidates(query))
    if "memory" in corpus:
        out.extend(memory_candidates(query))
    if "specs" in corpus:
        out.extend(spec_candidates(query))
    if "handoff" in corpus:
        out.extend(handoff_candidates(query))
    out.sort(key=lambda c: (-c.score, SOURCE_ORDER.get(c.source_class, 99), c.path, c.title))
    return out


def as_text(candidates: list[Candidate], query: str) -> str:
    if not candidates:
        return f'context-retrieve: no matches for query="{query}"\n'
    lines = [f'context-retrieve: query="{query}"']
    for idx, c in enumerate(candidates, 1):
        lines.append(
            f"{idx}. {c.path} [{c.source_class}; {c.authority}; score={c.score}]"
        )
        lines.append(f"   title: {c.title}")
        lines.append(f"   reason: {c.reason}")
        lines.append(f"   freshness: {c.freshness}")
        lines.append(f"   read_before_acting: {c.read_before_acting}")
        lines.append(f"   snippet: {c.snippet}")
    return "\n".join(lines) + "\n"


def as_capsules(candidates: list[Candidate]) -> str:
    blocks: list[str] = []
    for c in candidates:
        snippet = compact(c.snippet, 140)
        blocks.append(
            "\n".join(
                [
                    "▸ ---",
                    f"source: {c.path}",
                    f"source_class: {c.source_class}",
                    f"authority: {c.authority}",
                    f"title: {c.title}",
                    f"anchor: {c.anchor}",
                    f"reason: {c.reason}; score={c.score}",
                    f"freshness: {c.freshness}",
                    f"capsule: {c.read_before_acting} Snippet: {snippet}",
                ]
            )
        )
    return ("\n".join(blocks) + "\n") if blocks else ""


def as_debug(
    query: str,
    corpus: set[str],
    returned: list[Candidate],
    omitted: list[Candidate],
    limit: int,
    excludes: set[str],
) -> str:
    lines = [
        "CONTEXT_RETRIEVE_DEBUG",
        f"query: {query}",
        f"corpus: {','.join(sorted(corpus))}",
        f"limit: {limit}",
        "cache: none (v1 uses live files; .agent0/.context-index/ is reserved)",
        f"excluded_sources: {','.join(sorted(excludes)) if excludes else '(none)'}",
        "returned:",
    ]
    if returned:
        for c in returned:
            lines.append(
                f"- {c.path} | source_class={c.source_class} authority={c.authority} score={c.score} freshness={c.freshness} reason={c.reason}"
            )
    else:
        lines.append("- (none)")
    lines.append("omitted:")
    if omitted:
        for c in omitted[:20]:
            lines.append(f"- {c.path} | score={c.score} reason={c.reason}")
    else:
        lines.append("- (none)")
    lines.append("END_CONTEXT_RETRIEVE_DEBUG")
    return "\n".join(lines) + "\n"


def parse_corpus(value: str) -> set[str]:
    if value in ("", "all"):
        return set(DEFAULT_CORPUS)
    allowed = set(DEFAULT_CORPUS)
    selected = {part.strip() for part in value.split(",") if part.strip()}
    unknown = selected - allowed
    if unknown:
        sys.stderr.write(f"context-retrieve-helper: unknown corpus: {','.join(sorted(unknown))}\n")
        sys.exit(2)
    return selected


def cmd_search(args: argparse.Namespace) -> None:
    query = args.query or " ".join(args.query_parts or [])
    if not query.strip():
        sys.stderr.write("context-retrieve-helper: --query is required\n")
        sys.exit(2)
    corpus = parse_corpus(args.corpus)
    excludes = set(args.exclude_source or [])
    all_hits = [c for c in collect(query, corpus) if c.path not in excludes]
    returned = all_hits[: args.limit]
    omitted = all_hits[args.limit :]

    if args.format == "json":
        payload = {
            "query": query,
            "corpus": sorted(corpus),
            "limit": args.limit,
            "cache": "none",
            "candidates": [asdict(c) for c in returned],
            "omitted": [asdict(c) for c in omitted],
        }
        print(json.dumps(payload, indent=2, sort_keys=True))
    elif args.format == "capsules":
        sys.stdout.write(as_capsules(returned))
    elif args.format == "debug":
        sys.stdout.write(as_debug(query, corpus, returned, omitted, args.limit, excludes))
    else:
        sys.stdout.write(as_text(returned, query))


def main() -> None:
    parser = argparse.ArgumentParser(prog="context-retrieve-helper.py")
    sub = parser.add_subparsers(dest="cmd", required=True)
    search = sub.add_parser("search")
    search.add_argument("query_parts", nargs="*")
    search.add_argument("--query", default="")
    search.add_argument("--format", choices=("text", "json", "capsules", "debug"), default="text")
    search.add_argument("--limit", type=int, default=5)
    search.add_argument("--corpus", default="all")
    search.add_argument("--exclude-source", action="append", default=[])
    search.set_defaults(func=cmd_search)
    args = parser.parse_args()
    if args.limit < 1:
        sys.stderr.write("context-retrieve-helper: --limit must be >= 1\n")
        sys.exit(2)
    args.func(args)


if __name__ == "__main__":
    main()
