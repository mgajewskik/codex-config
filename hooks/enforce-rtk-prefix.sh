#!/usr/bin/env bash
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Codex PreToolUse does not currently support transparent updatedInput rewrites.
# Enforce RTK with a deny-and-retry hint instead of executing rewritten commands.

if ! command -v rtk >/dev/null 2>&1; then
    exit 0
fi

. "$SCRIPT_DIR/lib.sh"

init_hook_input || exit 0

if [[ -z "$COMMAND" ]]; then
    exit 0
fi

if [[ "$NORMALIZED_COMMAND" =~ ^[[:space:]]*rtk($|[[:space:]]) ]]; then
    exit 0
fi

REWRITTEN="$(rtk rewrite "$COMMAND" 2>/dev/null)"
REWRITE_STATUS=$?

case "$REWRITE_STATUS" in
    0|3)
        if [[ -z "$REWRITTEN" ]]; then
            exit 0
        fi

        if [[ "$REWRITTEN" == "$COMMAND" || "$REWRITTEN" == "$NORMALIZED_COMMAND" ]]; then
            exit 0
        fi

        printf -v reason 'RTK enforcement: rerun this Bash command through RTK to reduce token usage.\nCommand: %s\nSuggested: %s' "$(command_for_reason)" "$REWRITTEN"
        append_blocked_log "$reason" "rtk-prefix-enforcement" "$REWRITTEN"
        deny_pre_tool_use "$reason"
        ;;
    1)
        exit 0
        ;;
    2)
        printf -v reason 'RTK enforcement: command matched an RTK deny rule.\nCommand: %s' "$(command_for_reason)"
        append_blocked_log "$reason" "rtk-permission-deny" ""
        deny_pre_tool_use "$reason"
        ;;
    *)
        exit 0
        ;;
esac
