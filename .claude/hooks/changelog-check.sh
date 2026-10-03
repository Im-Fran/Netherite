#!/bin/sh
# Stop hook: before Claude finishes, ask it to record pending changes under
# "## [Unreleased]" in CHANGELOG.md. Runs once per stop (stop_hook_active),
# so Claude can still end the turn when a change isn't user-visible.
input=$(cat)
case "$input" in *'"stop_hook_active":true'*|*'"stop_hook_active": true'*) exit 0 ;; esac

cd "${CLAUDE_PROJECT_DIR:-.}" || exit 0
changed=$(git status --porcelain 2>/dev/null)
case "$changed" in *CHANGELOG.md*) exit 0 ;; esac
# Only source, project and build changes count; docs and tooling don't ship.
echo "$changed" | grep -qE '(Netherite|Packages|ShareExtension|Widgets)/|project\.yml' || exit 0

cat <<'JSON'
{"decision": "block", "reason": "There are uncommitted app changes but CHANGELOG.md was not updated. Add user-facing entries under '## [Unreleased]' in CHANGELOG.md (### Added / Changed / Deprecated / Removed / Fixed / Security, one '- ' bullet per change, written for users, in English). If the changes are not user-visible (refactors, tests, internal tooling), say so and stop without editing it."}
JSON
