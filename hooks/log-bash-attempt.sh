#!/usr/bin/env bash
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Codex PreToolUse currently only protects Bash commands and is not a complete
# security boundary. This hook only records the Bash command Codex is attempting.
# It does not log command output.
. "$SCRIPT_DIR/lib.sh"

init_hook_input || exit 0
append_bash_log
