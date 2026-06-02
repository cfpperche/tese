#!/usr/bin/env bash
set -euo pipefail

# claude-exec — launch the local Claude Code CLI as a bounded non-interactive
# subprocess and capture its output. Sibling in purpose to codex-exec (one
# runtime invokes another model's brain), but built around `claude -p`:
# native permission-mode pass-through (required, no default), tool allowlists,
# and jq-based last-message extraction (Claude has no --output-last-message).

usage() {
  cat <<'EOF'
Usage: claude-exec.sh --permission-mode <mode> [options] (--task <prompt> | --task-file <path> | prompt via stdin | -- <prompt...>)

Required:
  --permission-mode <mode>  default | plan | acceptEdits | bypassPermissions | dontAsk | auto
                            Forwarded verbatim to `claude --permission-mode`. No default — fail-closed.

Options:
  --allow-writes            Required confirmation for write/execute-capable modes
                            (acceptEdits, bypassPermissions, dontAsk, auto). Without it,
                            those modes are refused; default/plan are the read-only floor.
  --task <text>             Prompt sent to Claude.
  --task-file <path>        Read prompt text from a file.
  --allowedTools <list>     Space/comma-separated tools to allow (e.g. "Read Grep Glob").
  --disallowedTools <list>  Space/comma-separated tools to deny.
  --model <model>           Claude model alias or full name.
  --reasoning-effort <lvl>  low|medium|high|xhigh|max (maps to claude --effort). Alias: --effort.
  --add-dir <dir>           Extra dir Claude may access; must resolve under the repo root.
  --bare                    Opt-in: skip hooks/CLAUDE.md/auto-memory (cheap isolated probe).
                            Note: forces auth to ANTHROPIC_API_KEY (breaks OAuth/subscription).
  --json                    Use stream-json and capture JSONL events to events.jsonl.
  --resume <session-id>     Continue an existing Claude session (claude -p --resume <id>).
  --output <path>           Path for last-message.md; must stay under the state dir.
  --slug <slug>             Slug for the generated run directory.
  -h, --help                Show this help.
EOF
}

die() {
  printf 'claude-exec error: %s\n' "$*" >&2
  exit 2
}

json_escape() {
  local s=${1//\\/\\\\}
  s=${s//\"/\\\"}
  s=${s//$'\n'/\\n}
  s=${s//$'\r'/\\r}
  s=${s//$'\t'/\\t}
  printf '%s' "$s"
}

json_string() {
  printf '"%s"' "$(json_escape "$1")"
}

require_value() {
  local opt=$1
  local value=${2-}
  if [ -z "$value" ]; then
    die "$opt requires a value"
  fi
}

abs_dir() {
  local dir=$1
  [ -d "$dir" ] || die "directory does not exist: $dir"
  (cd "$dir" && pwd -P)
}

derive_slug() {
  local raw slug
  raw=$1
  slug=$(
    printf '%s' "$raw" |
      tr '[:upper:]' '[:lower:]' |
      tr -cs '[:alnum:]' '-' |
      sed 's/^-*//; s/-*$//; s/--*/-/g; s/^\(.\{1,48\}\).*/\1/; s/-$//'
  )
  if [ -z "$slug" ]; then
    slug="task"
  fi
  case "$slug" in
    [a-z]*) ;;
    *) slug="task-$slug" ;;
  esac
  printf '%s' "$slug"
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd -P)"
STATE_ROOT="${CLAUDE_EXEC_STATE_DIR:-$ROOT/.agent0/.runtime-state/claude-exec}"

task=""
task_file=""
permission_mode=""
allowed_tools=""
disallowed_tools=""
model=""
reasoning_effort=""
add_dir=""
bare=0
allow_writes=0
json=0
resume_id=""
output_path=""
slug=""
positional=()

while [ "$#" -gt 0 ]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --task)
      shift; require_value "--task" "${1-}"; task=$1 ;;
    --task=*)
      task=${1#--task=}; require_value "--task" "$task" ;;
    --task-file)
      shift; require_value "--task-file" "${1-}"; task_file=$1 ;;
    --task-file=*)
      task_file=${1#--task-file=}; require_value "--task-file" "$task_file" ;;
    --permission-mode)
      shift; require_value "--permission-mode" "${1-}"; permission_mode=$1 ;;
    --permission-mode=*)
      permission_mode=${1#--permission-mode=}; require_value "--permission-mode" "$permission_mode" ;;
    --allowedTools|--allowed-tools)
      shift; require_value "--allowedTools" "${1-}"; allowed_tools=$1 ;;
    --allowedTools=*|--allowed-tools=*)
      allowed_tools=${1#*=}; require_value "--allowedTools" "$allowed_tools" ;;
    --disallowedTools|--disallowed-tools)
      shift; require_value "--disallowedTools" "${1-}"; disallowed_tools=$1 ;;
    --disallowedTools=*|--disallowed-tools=*)
      disallowed_tools=${1#*=}; require_value "--disallowedTools" "$disallowed_tools" ;;
    --model|-m)
      shift; require_value "--model" "${1-}"; model=$1 ;;
    --model=*)
      model=${1#--model=}; require_value "--model" "$model" ;;
    --reasoning-effort|--effort)
      shift; require_value "--reasoning-effort" "${1-}"; reasoning_effort=$1 ;;
    --reasoning-effort=*|--effort=*)
      reasoning_effort=${1#*=}; require_value "--reasoning-effort" "$reasoning_effort" ;;
    --add-dir)
      shift; require_value "--add-dir" "${1-}"; add_dir=$1 ;;
    --add-dir=*)
      add_dir=${1#--add-dir=}; require_value "--add-dir" "$add_dir" ;;
    --bare)
      bare=1 ;;
    --allow-writes)
      allow_writes=1 ;;
    --json)
      json=1 ;;
    --resume)
      shift; require_value "--resume" "${1-}"; resume_id=$1 ;;
    --resume=*)
      resume_id=${1#--resume=}; require_value "--resume" "$resume_id" ;;
    --output|-o)
      shift; require_value "--output" "${1-}"; output_path=$1 ;;
    --output=*)
      output_path=${1#--output=}; require_value "--output" "$output_path" ;;
    --slug)
      shift; require_value "--slug" "${1-}"; slug=$1 ;;
    --slug=*)
      slug=${1#--slug=}; require_value "--slug" "$slug" ;;
    --)
      shift
      while [ "$#" -gt 0 ]; do positional+=("$1"); shift; done
      break
      ;;
    -*)
      die "unknown option: $1" ;;
    *)
      positional+=("$1") ;;
  esac
  shift || true
done

# Permission mode is required and fail-closed — no default.
if [ -z "$permission_mode" ]; then
  die "--permission-mode is required (default|plan|acceptEdits|bypassPermissions|dontAsk|auto)"
fi
case "$permission_mode" in
  default|plan|acceptEdits|bypassPermissions|dontAsk|auto) ;;
  *) die "invalid --permission-mode '$permission_mode' (expected default, plan, acceptEdits, bypassPermissions, dontAsk, or auto)" ;;
esac

# Floor invariant: write/execute-capable modes require explicit --allow-writes.
# default and plan are the read-only floor and pass without confirmation.
case "$permission_mode" in
  acceptEdits|bypassPermissions|dontAsk|auto)
    if [ "$allow_writes" -ne 1 ]; then
      die "permission mode '$permission_mode' is write-capable; pass --allow-writes to confirm intent (default/plan are the read-only floor)"
    fi
    ;;
esac

# Reasoning effort, when given, must be a level claude --effort accepts.
case "$reasoning_effort" in
  ""|low|medium|high|xhigh|max) ;;
  *) die "invalid --reasoning-effort '$reasoning_effort' (expected low, medium, high, xhigh, or max)" ;;
esac

# Resolve the prompt from exactly one source.
if [ -n "$task_file" ]; then
  [ -f "$task_file" ] || die "task file does not exist: $task_file"
  if [ -n "$task" ] || [ "${#positional[@]}" -gt 0 ]; then
    die "use only one prompt source: --task, --task-file, stdin, or -- <prompt>"
  fi
  task=$(cat "$task_file")
elif [ -z "$task" ] && [ "${#positional[@]}" -gt 0 ]; then
  task="${positional[*]}"
elif [ -z "$task" ] && [ ! -t 0 ]; then
  task=$(cat)
fi

if [ -z "$task" ]; then
  die "missing task prompt"
fi

# Dependency checks — fail before creating a success-looking output dir.
command -v claude >/dev/null 2>&1 || die "claude CLI is not on PATH"
command -v jq >/dev/null 2>&1 || die "jq is required to extract Claude's final message but is not on PATH"

ROOT_REAL="$(abs_dir "$ROOT")"
case "$STATE_ROOT" in
  /*) ;;
  *) STATE_ROOT="$ROOT/$STATE_ROOT" ;;
esac
STATE_ROOT_REAL="$(realpath -m "$STATE_ROOT")"
STATE_ROOT="$STATE_ROOT_REAL"

# --add-dir, when given, must resolve under the repo root.
add_dir_real=""
if [ -n "$add_dir" ]; then
  case "$add_dir" in
    /*) ;;
    *) add_dir="$ROOT/$add_dir" ;;
  esac
  add_dir_real="$(abs_dir "$add_dir")"
  case "$add_dir_real" in
    "$ROOT_REAL"|"$ROOT_REAL"/*) ;;
    *) die "--add-dir must resolve under repo root: $ROOT_REAL" ;;
  esac
fi

if [ -n "$slug" ]; then
  case "$slug" in
    [a-z]*)
      if ! printf '%s' "$slug" | grep -Eq '^[a-z][a-z0-9-]*$'; then
        die "--slug must be kebab-case"
      fi
      ;;
    *) die "--slug must start with a lowercase letter" ;;
  esac
else
  slug=$(derive_slug "$task")
fi

timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
iso_ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

if [ -n "$output_path" ]; then
  case "$output_path" in
    /*) ;;
    *) output_path="$STATE_ROOT/$output_path" ;;
  esac
  output_path="$(realpath -m "$output_path")"
  output_parent="$(dirname "$output_path")"
  case "$output_parent" in
    "$STATE_ROOT_REAL"|"$STATE_ROOT_REAL"/*) ;;
    *) die "--output must resolve under state dir: $STATE_ROOT_REAL" ;;
  esac
  mkdir -p "$(dirname "$output_path")"
  run_dir="$(cd "$(dirname "$output_path")" && pwd -P)"
  last_message="$output_path"
else
  run_dir="$STATE_ROOT/$timestamp-$slug"
  last_message="$run_dir/last-message.md"
fi

mkdir -p "$run_dir"

prompt_file="$run_dir/prompt.md"
stderr_file="$run_dir/stderr.txt"
metadata_file="$run_dir/metadata.json"
command_file="$run_dir/command.txt"
if [ "$json" -eq 1 ]; then
  stdout_file="$run_dir/events.jsonl"
  output_format="stream-json"
else
  stdout_file="$run_dir/stdout.txt"
  output_format="json"
fi

printf '%s\n' "$task" > "$prompt_file"

# Build the claude argv. Prompt always arrives via stdin so variadic flags
# (--allowedTools, --add-dir) never swallow it.
cmd=(claude -p --permission-mode "$permission_mode" --output-format "$output_format")
if [ "$output_format" = "stream-json" ]; then
  cmd+=(--verbose)
fi
if [ -n "$model" ]; then
  cmd+=(--model "$model")
fi
if [ -n "$reasoning_effort" ]; then
  cmd+=(--effort "$reasoning_effort")
fi
if [ -n "$allowed_tools" ]; then
  cmd+=(--allowedTools "$allowed_tools")
fi
if [ -n "$disallowed_tools" ]; then
  cmd+=(--disallowedTools "$disallowed_tools")
fi
if [ -n "$add_dir_real" ]; then
  cmd+=(--add-dir "$add_dir_real")
fi
if [ "$bare" -eq 1 ]; then
  cmd+=(--bare)
fi
if [ -n "$resume_id" ]; then
  cmd+=(--resume "$resume_id")
fi

printf '%q ' "${cmd[@]}" > "$command_file"
printf '\n' >> "$command_file"

set +e
"${cmd[@]}" < "$prompt_file" > "$stdout_file" 2> "$stderr_file"
exit_code=$?
set -e

# Extract the final message + session id from Claude's JSON output. Both the
# single-object (json) and JSONL (stream-json) forms carry a type=="result"
# record with .result and .session_id.
session_id=""
if [ -s "$stdout_file" ]; then
  jq -r 'select(.type=="result")|.result // empty' "$stdout_file" 2>/dev/null > "$last_message" || : > "$last_message"
  session_id="$(jq -r 'select(.type=="result")|.session_id // empty' "$stdout_file" 2>/dev/null | head -n1)"
fi
if [ ! -f "$last_message" ]; then
  : > "$last_message"
fi

{
  printf '{\n'
  printf '  "ts": %s,\n' "$(json_string "$iso_ts")"
  printf '  "slug": %s,\n' "$(json_string "$slug")"
  printf '  "permission_mode": %s,\n' "$(json_string "$permission_mode")"
  printf '  "allowed_tools": %s,\n' "$(json_string "$allowed_tools")"
  printf '  "disallowed_tools": %s,\n' "$(json_string "$disallowed_tools")"
  printf '  "model": %s,\n' "$(json_string "$model")"
  printf '  "reasoning_effort": %s,\n' "$(json_string "$reasoning_effort")"
  printf '  "add_dir": %s,\n' "$(json_string "$add_dir_real")"
  printf '  "bare": %s,\n' "$([ "$bare" -eq 1 ] && printf true || printf false)"
  printf '  "allow_writes": %s,\n' "$([ "$allow_writes" -eq 1 ] && printf true || printf false)"
  printf '  "json": %s,\n' "$([ "$json" -eq 1 ] && printf true || printf false)"
  printf '  "resume_id": %s,\n' "$(json_string "$resume_id")"
  printf '  "session_id": %s,\n' "$(json_string "$session_id")"
  printf '  "exit_code": %s,\n' "$exit_code"
  printf '  "prompt_file": %s,\n' "$(json_string "$prompt_file")"
  printf '  "last_message": %s,\n' "$(json_string "$last_message")"
  printf '  "stdout_file": %s,\n' "$(json_string "$stdout_file")"
  printf '  "stderr_file": %s,\n' "$(json_string "$stderr_file")"
  printf '  "command_file": %s\n' "$(json_string "$command_file")"
  printf '}\n'
} > "$metadata_file"

{
  printf '{"ts":%s,' "$(json_string "$iso_ts")"
  printf '"slug":%s,' "$(json_string "$slug")"
  printf '"permission_mode":%s,' "$(json_string "$permission_mode")"
  printf '"model":%s,' "$(json_string "$model")"
  printf '"reasoning_effort":%s,' "$(json_string "$reasoning_effort")"
  printf '"bare":%s,' "$([ "$bare" -eq 1 ] && printf true || printf false)"
  printf '"json":%s,' "$([ "$json" -eq 1 ] && printf true || printf false)"
  printf '"resume_id":%s,' "$(json_string "$resume_id")"
  printf '"session_id":%s,' "$(json_string "$session_id")"
  printf '"exit_code":%s,' "$exit_code"
  printf '"run_dir":%s,' "$(json_string "$run_dir")"
  printf '"last_message":%s,' "$(json_string "$last_message")"
  printf '"stdout_file":%s,' "$(json_string "$stdout_file")"
  printf '"stderr_file":%s,' "$(json_string "$stderr_file")"
  printf '"metadata":%s}\n' "$(json_string "$metadata_file")"
} >> "$STATE_ROOT/runs.jsonl"

printf 'claude-exec: exit_code=%s\n' "$exit_code"
printf 'run_dir=%s\n' "$run_dir"
printf 'last_message=%s\n' "$last_message"
printf 'session_id=%s\n' "$session_id"
printf 'stdout_file=%s\n' "$stdout_file"
printf 'stderr_file=%s\n' "$stderr_file"
printf 'metadata=%s\n' "$metadata_file"

exit "$exit_code"
