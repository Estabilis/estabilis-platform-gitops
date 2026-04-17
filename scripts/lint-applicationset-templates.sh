#!/usr/bin/env bash
# lint-applicationset-templates.sh
#
# Enforces ArgoCD ApplicationSet goTemplate syntax inside
# `workload-bootstrap/templates/*.yaml`.
#
# Background: when an ApplicationSet declares `goTemplate: true`, the
# controller reinterprets strings wrapped in backticks inside the outer
# Helm template. That inner reinterpretation requires:
#   1) spaces after `{{` and before `}}`
#   2) a leading `.` on cluster generator variables (`.name`, `.server`)
#
# Without goTemplate, the legacy syntax `{{name}}` / `{{server}}` works.
# This lint is therefore contextual: it only fires on files that declare
# `goTemplate: true`, to avoid flagging legitimate legacy-mode templates.
#
# See: .agent-notes/2026-04-17-applicationset-gotemplate-syntax.md

set -euo pipefail

TEMPLATE_DIR="${LINT_TEMPLATE_DIR:-workload-bootstrap/templates}"

if [ ! -d "$TEMPLATE_DIR" ]; then
    echo "lint-applicationset-templates: directory not found: $TEMPLATE_DIR" >&2
    exit 2
fi

exit_code=0
checked=0
skipped=0

for file in "$TEMPLATE_DIR"/*.yaml; do
    [ -f "$file" ] || continue

    # Only lint ApplicationSets in goTemplate mode. Legacy-mode files
    # legitimately use `{{name}}` without spaces or dot — skip them.
    if ! grep -Eq '^[[:space:]]*goTemplate:[[:space:]]*true' "$file"; then
        skipped=$((skipped + 1))
        continue
    fi
    checked=$((checked + 1))

    # Violation A: backtick immediately followed by `{{` with no space
    # after the braces (e.g. `{{index ...`, `{{name}}`).
    v_open=$(grep -nE '`\{\{[^ `]' "$file" || true)

    # Violation B: `}}` immediately preceded by a non-space character
    # and followed by a backtick (e.g. `...annotations"}}`).
    v_close=$(grep -nE '[^ ]\}\}`' "$file" || true)

    # Violation C: legacy placeholders inside backticks without leading
    # dot. Required under goTemplate: true.
    v_legacy=$(grep -nE '`\{\{(name|server)\}\}`' "$file" || true)

    if [ -n "$v_open" ] || [ -n "$v_close" ] || [ -n "$v_legacy" ]; then
        echo "[FAIL] $file"
        [ -n "$v_open" ]   && printf '%s\n' "$v_open"   | sed 's/^/        missing space after {{ : /'
        [ -n "$v_close" ]  && printf '%s\n' "$v_close"  | sed 's/^/        missing space before }}: /'
        [ -n "$v_legacy" ] && printf '%s\n' "$v_legacy" | sed 's/^/        legacy placeholder needs leading dot: /'
        echo
        exit_code=1
    fi
done

if [ "$exit_code" -eq 0 ]; then
    echo "lint-applicationset-templates: OK (checked=$checked goTemplate files, skipped=$skipped legacy files)"
else
    echo "lint-applicationset-templates: FAIL — see violations above" >&2
    echo "Reference: .agent-notes/2026-04-17-applicationset-gotemplate-syntax.md" >&2
fi

exit $exit_code
