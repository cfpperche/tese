#!/usr/bin/env python3
# .agent0/skills/brainstorm/scripts/render.py
#
# Deterministic renderer for the /brainstorm `done` step. Pure function:
# state.json -> self-contained HTML. ALL eight template placeholders are
# mechanical transformations of the captured state — no judgment happens at
# render time (tagging/classification/lens application all happened DURING the
# session and are already baked into the JSON). Extracting this out of the
# SKILL.md prose makes `done` deterministic and gives brainstorm its first
# testable surface, and works identically on any runtime that has python3.
#
# Usage:
#   python3 render.py <state.json> [--template <path>] [--out <path>]
#
# Defaults: template = <script_dir>/../templates/render.html.tmpl
#           out      = <state.json path> with .json -> .html
#
# Reference:
#   .agent0/skills/brainstorm/SKILL.md          § Subcommand: `done`
#   .agent0/skills/brainstorm/templates/render.html.tmpl
import argparse
import html
import json
import os
import sys

TAGS = ["easy", "risky", "wild", "unknown"]


def esc(s):
    """HTML-escape a value for text/attribute context."""
    return html.escape(str(s if s is not None else ""), quote=True)


def truncate(s, n):
    s = str(s if s is not None else "")
    return s if len(s) <= n else s[: n - 1].rstrip() + "…"


def kebab(name):
    """Lowercase, collapse non-alphanumerics to single hyphens, trim. Mirrors the
    template JS slug (line ~250): name.toLowerCase().replace(/[^a-z0-9]+/g,'-')."""
    out = []
    prev_dash = False
    for ch in str(name).lower():
        if ch.isalnum():
            out.append(ch)
            prev_dash = False
        else:
            if not prev_dash:
                out.append("-")
            prev_dash = True
    return "".join(out).strip("-")


def css_slug(slug):
    """Badge CSS class aliasing per template: six-thinking-hats -> six-hats."""
    return "six-hats" if slug == "six-thinking-hats" else slug


def tag_of(idea):
    t = idea.get("tag")
    return t if t in TAGS else "unknown"


def build_mindmap_markdown(state):
    """Markmap source: topic heading -> tag buckets -> idea texts (<=80 chars)
    -> derived-from provenance as a nested `↳ via <lens>` node. Skip empty
    buckets. (SKILL.md § done, {{MINDMAP_MARKDOWN}}.)"""
    lines = ["# " + str(state.get("topic", "brainstorm"))]
    buckets = {t: [] for t in TAGS}
    for idea in state.get("ideas", []):
        buckets[tag_of(idea)].append(idea)
    for t in TAGS:
        ideas = buckets[t]
        if not ideas:
            continue
        lines.append("## " + t)
        for idea in ideas:
            lines.append("- " + truncate(idea.get("text", ""), 80))
            if idea.get("lens") and idea.get("derived_from") is not None:
                lines.append("  - ↳ via " + str(idea["lens"]))
    return "\n".join(lines)


def build_lens_tabs(state):
    """One tab button per applied lens. data-tab must match the panel's
    data-panel (`lens-<slug>`)."""
    out = []
    for lens in state.get("lenses_applied", []):
        slug = kebab(lens.get("name", ""))
        out.append(
            '<button data-tab="lens-%s">%s</button>' % (slug, esc(lens.get("name", "")))
        )
    return "\n    ".join(out)


def build_lens_panels(state):
    """One panel per applied lens. The kanban host id `kanban-<slug>` is filled
    client-side by the template JS from STATE.ideas filtered by lens. Six
    Thinking Hats renders one sub-section per applied hat when capture data is
    present under lens.six_hats.<hat>."""
    out = []
    for lens in state.get("lenses_applied", []):
        name = lens.get("name", "")
        slug = kebab(name)
        badge = css_slug(slug)
        parts = [
            '  <div class="panel" data-panel="lens-%s">' % slug,
            "    <section>",
            '      <h2>%s <span class="lens-badge %s">%s</span> &mdash; derived ideas</h2>'
            % (esc(name), badge, esc(name)),
            '      <div class="kanban" id="kanban-%s"></div>' % slug,
        ]
        six = lens.get("six_hats")
        if isinstance(six, dict) and six:
            for hat, captures in six.items():
                if not captures:
                    continue
                items = captures if isinstance(captures, list) else [captures]
                parts.append('      <div class="lens-section">')
                parts.append("        <h3>%s hat</h3>" % esc(hat))
                parts.append('        <ul class="qs">')
                for c in items:
                    text = c.get("text", c) if isinstance(c, dict) else c
                    parts.append("          <li>%s</li>" % esc(text))
                parts.append("        </ul>")
                parts.append("      </div>")
        parts.append("    </section>")
        parts.append("  </div>")
        out.append("\n".join(parts))
    return "\n".join(out)


def build_timeline_mermaid(state):
    """mermaid `timeline` from turns[]. Mermaid uses `:` as the field delimiter,
    so colons inside a summary break the diagram — replace with an em dash.
    Truncate each summary to 60 chars."""
    lines = ["timeline", "    title brainstorm session"]
    for turn in state.get("turns", []):
        n = turn.get("n", "")
        # Normalize any colon to a spaced em dash: ": " and bare ":" both → " — ".
        summary = truncate(turn.get("summary", ""), 60).replace(": ", " — ").replace(
            ":", " — "
        )
        lines.append("    turn %s : %s" % (n, summary))
    return "\n".join(lines)


def embed_state_json(state):
    """Full state as a JS literal. Escape `</` so a string value can't break out
    of the enclosing <script> tag (SKILL.md § done, {{STATE_JSON}})."""
    return json.dumps(state, ensure_ascii=False).replace("</", "<\\/")


def human_timestamp(state):
    started = state.get("started_at", "") or ""
    ended = state.get("ended_at", "") or ""
    return ("%s → %s" % (started, ended)) if ended else started


def render(state, template):
    repl = {
        "{{TOPIC}}": esc(state.get("topic", "brainstorm")),
        "{{TIMESTAMP}}": esc(human_timestamp(state)),
        "{{IDEAS_COUNT}}": str(len(state.get("ideas", []))),
        "{{QUESTIONS_COUNT}}": str(len(state.get("questions_open", []))),
        "{{LENSES_COUNT}}": str(len(state.get("lenses_applied", []))),
        "{{LENS_TABS_HTML}}": build_lens_tabs(state),
        "{{LENS_PANELS_HTML}}": build_lens_panels(state),
        "{{MINDMAP_MARKDOWN}}": build_mindmap_markdown(state),
        "{{TIMELINE_MERMAID}}": build_timeline_mermaid(state),
        "{{STATE_JSON}}": embed_state_json(state),
    }
    out = template
    for key, val in repl.items():
        out = out.replace(key, val)
    return out


def main(argv):
    ap = argparse.ArgumentParser(description="Render a brainstorm state JSON to HTML.")
    ap.add_argument("state", help="path to the brainstorm state .json")
    ap.add_argument("--template", help="path to render.html.tmpl (default: bundled)")
    ap.add_argument("--out", help="output HTML path (default: state path with .html)")
    args = ap.parse_args(argv)

    script_dir = os.path.dirname(os.path.abspath(__file__))
    template_path = args.template or os.path.join(
        script_dir, "..", "templates", "render.html.tmpl"
    )

    try:
        with open(args.state, "r", encoding="utf-8") as f:
            state = json.load(f)
    except FileNotFoundError:
        sys.stderr.write("render: state file not found: %s\n" % args.state)
        return 2
    except json.JSONDecodeError as e:
        sys.stderr.write("render: state is not valid JSON: %s\n" % e)
        return 2

    try:
        with open(template_path, "r", encoding="utf-8") as f:
            template = f.read()
    except FileNotFoundError:
        sys.stderr.write("render: template not found: %s\n" % template_path)
        return 2

    out_path = args.out
    if not out_path:
        base = args.state
        out_path = (base[:-5] if base.endswith(".json") else base) + ".html"

    html_out = render(state, template)
    with open(out_path, "w", encoding="utf-8") as f:
        f.write(html_out)

    # Leftover-placeholder guard — proves every token was substituted.
    leftover = [
        k
        for k in (
            "{{TOPIC}}",
            "{{TIMESTAMP}}",
            "{{IDEAS_COUNT}}",
            "{{QUESTIONS_COUNT}}",
            "{{LENSES_COUNT}}",
            "{{LENS_TABS_HTML}}",
            "{{LENS_PANELS_HTML}}",
            "{{MINDMAP_MARKDOWN}}",
            "{{TIMELINE_MERMAID}}",
            "{{STATE_JSON}}",
        )
        if k in html_out
    ]
    if leftover:
        sys.stderr.write("render: WARNING unsubstituted placeholders: %s\n" % leftover)
        return 1

    sys.stdout.write(out_path + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
