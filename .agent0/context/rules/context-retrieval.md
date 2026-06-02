---
paths:
  - ".agent0/tools/context-retrieve.sh"
  - ".agent0/tools/context-retrieve-helper.py"
  - ".agent0/hooks/context-inject.sh"
  - ".agent0/.context-index/"
---

# Context retrieval

Agent0 v1 context retrieval is a deterministic, local context-engineering primitive. It is not semantic RAG in v1: no embeddings, vector database, hosted retrieval service, API key, paid dependency, background daemon, or product-code indexing is required.

## Source of truth

Retrieval returns source-backed pointers. It never replaces the source files:

- context rules: `.agent0/context/rules/*.md`
- project memory: `.agent0/memory/MEMORY.md` plus entry metadata
- specs: `docs/specs/*/spec.md`
- handoff: `.agent0/HANDOFF.md`

Snippets are for disambiguation only. When a result has `authority=evidence-pointer`, read the referenced source before acting on the content. Rules hydrated as `authority=authoritative-capsule` remain pointers to trusted repo-controlled rule files; read the rule body when the task depends on omitted detail.

## Explicit search

Use the runtime-neutral tool:

```bash
bash .agent0/tools/context-retrieve.sh search --query "<text>"
bash .agent0/tools/context-retrieve.sh search --query "<text>" --format json
bash .agent0/tools/context-retrieve.sh search --query "<text>" --format debug
```

Each candidate reports `source_class`, `authority`, `path`, `title` or anchor, score/reason, freshness, read-before-acting guidance, and a short snippet.

## Prompt hydration

`context-inject.sh` uses retrieval as a bounded lane after deterministic floor selection:

1. The existing keyword/path-selected rule capsules form a must-include floor.
2. Retrieval candidates compete only for remaining `AGENT0_CONTEXT_MAX_FRAGMENTS` and `AGENT0_CONTEXT_MAX_BYTES` budget.
3. Normal prompt turns still emit one `AGENT0_CONTEXT_INJECTION` block, not a second retrieval dump.
4. Retrieval is fail-open: if the tool is missing or errors, deterministic context injection still works.

Set `AGENT0_CONTEXT_RETRIEVAL=0` to disable the retrieval lane for local debugging.

## Memory adapter

Memory participates through its existing projection and metadata. The retriever reads `MEMORY.md` and entry frontmatter freshness fields; it must not build a second canonical memory listing or token/text index over `.agent0/memory/*.md`.

## Generated state

`.agent0/.context-index/` is reserved for future generated retrieval cache and is gitignored. V1 searches live files and does not require persistent cache.
