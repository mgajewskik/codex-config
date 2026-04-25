#!/usr/bin/env bash

# Codex PreToolUse currently only protects Bash commands. These hooks are a
# useful guardrail, not a complete security boundary for all tool access.

set -u

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CODEX_DIR="$(cd "$HOOK_DIR/.." && pwd)"

timestamp_utc() {
    date -u +"%Y-%m-%dT%H:%M:%SZ"
}

hook_has_jq() {
    command -v jq >/dev/null 2>&1
}

trim_hook_value() {
    local value="$1"

    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    printf '%s' "$value"
}

init_hook_input() {
    hook_has_jq || return 1

    HOOK_PAYLOAD="$(cat)"

    if ! printf '%s' "$HOOK_PAYLOAD" | jq -e . >/dev/null 2>&1; then
        return 1
    fi

    CWD="$(printf '%s' "$HOOK_PAYLOAD" | jq -r '.cwd // empty')"
    SESSION_ID="$(printf '%s' "$HOOK_PAYLOAD" | jq -r '.session_id // empty')"
    TURN_ID="$(printf '%s' "$HOOK_PAYLOAD" | jq -r '.turn_id // empty')"
    HOOK_EVENT_NAME="$(printf '%s' "$HOOK_PAYLOAD" | jq -r '.hook_event_name // empty')"
    COMMAND="$(printf '%s' "$HOOK_PAYLOAD" | jq -r '.tool_input.command // empty')"

    if [[ -z "$CWD" ]]; then
        CWD="$(pwd)"
    fi

    NORMALIZED_COMMAND="$(printf '%s' "$COMMAND" | tr '\n' ' ')"
}

ensure_log_dir() {
    mkdir -p "$CWD/.codex/log"
}

append_bash_log() {
    local log_file="$CWD/.codex/log/bash-commands.jsonl"

    hook_has_jq || return 0
    ensure_log_dir || return 0
    jq -cn \
        --arg timestamp "$(timestamp_utc)" \
        --arg event "$HOOK_EVENT_NAME" \
        --arg session_id "$SESSION_ID" \
        --arg turn_id "$TURN_ID" \
        --arg command "$COMMAND" \
        '{timestamp:$timestamp,event:$event,session_id:$session_id,turn_id:$turn_id,command:$command}' \
        >>"$log_file"
}

append_blocked_log() {
    local reason="$1"
    local policy="$2"
    local pattern="$3"
    local log_file="$CWD/.codex/log/blocked-bash-commands.jsonl"

    hook_has_jq || return 0
    ensure_log_dir || return 0
    jq -cn \
        --arg timestamp "$(timestamp_utc)" \
        --arg event "$HOOK_EVENT_NAME" \
        --arg session_id "$SESSION_ID" \
        --arg turn_id "$TURN_ID" \
        --arg command "$COMMAND" \
        --arg reason "$reason" \
        --arg policy "$policy" \
        --arg pattern "$pattern" \
        '{timestamp:$timestamp,event:$event,session_id:$session_id,turn_id:$turn_id,command:$command,reason:$reason,policy:$policy,pattern:$pattern}' \
        >>"$log_file"
}

command_matches_patterns() {
    local pattern

    MATCHED_PATTERN=""

    for pattern in "$@"; do
        if [[ "$NORMALIZED_COMMAND" =~ $pattern ]]; then
            MATCHED_PATTERN="$pattern"
            return 0
        fi
    done

    return 1
}

deny_pre_tool_use() {
    local reason="$1"

    hook_has_jq || return 0
    jq -cn \
        --arg reason "$reason" \
        '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$reason}}'
}

command_for_reason() {
    printf '%s' "$NORMALIZED_COMMAND"
}
