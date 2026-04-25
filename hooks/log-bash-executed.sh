#!/usr/bin/env bash
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Codex PostToolUse currently only observes Bash results after execution. This
# hook is logging-only and does not log command output.
. "$SCRIPT_DIR/lib.sh"

init_hook_input || exit 0
append_bash_log
