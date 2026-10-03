#!/usr/bin/env bash
set -euo pipefail

usage() {
    printf 'Usage: %s <prompt-or-prd-file> <max-iterations> [iteration-timeout-seconds]\n' "$0" >&2
}

if [[ $# -lt 2 || $# -gt 3 ]]; then
    usage
    exit 64
fi

prompt_file=$1
max_iterations=$2
iteration_timeout=${3:-1800}

if [[ ! -f $prompt_file ]]; then
    printf 'Prompt/PRD file not found: %s\n' "$prompt_file" >&2
    exit 66
fi

if [[ ! $max_iterations =~ ^[1-9][0-9]*$ ]]; then
    printf 'Max iterations must be a positive integer.\n' >&2
    exit 64
fi

if [[ ! $iteration_timeout =~ ^[1-9][0-9]*$ ]]; then
    printf 'Iteration timeout must be a positive integer in seconds.\n' >&2
    exit 64
fi

if ! command -v timeout >/dev/null; then
    printf 'GNU timeout is required.\n' >&2
    exit 69
fi

if [[ ! -d .git || -L .git ]]; then
    printf 'Run this loop from the root of a normal Git checkout (.git must be a real directory).\n' >&2
    exit 65
fi

workspace_root=$(pwd -P)
if ! repo_root=$(git rev-parse --show-toplevel 2>/dev/null) || [[ $repo_root != "$workspace_root" ]]; then
    printf 'Run this loop from the repository root.\n' >&2
    exit 65
fi

# Quote the physical Git path as a TOML key for the CLI override.
git_metadata_path=${workspace_root//\\/\\\\}
git_metadata_path=${git_metadata_path//\"/\\\"}
git_permission="permissions.loop.filesystem={\"$git_metadata_path/.git\"=\"write\"}"

attempt_stderr=$(mktemp /tmp/codex-loop.XXXXXX)
trap 'rm -f -- "$attempt_stderr"' EXIT

is_transient_error() {
    local error_line status_error transport_error
    error_line=$(grep -E '^(ERROR|Error|error):' "$attempt_stderr" | tail -n 1 || true)
    if printf '%s\n' "$error_line" | grep -Eiq \
        'configuration|config\.toml|invalid api key|authentication|unauthorized|forbidden|permission denied|access denied'; then
        return 1
    fi
    status_error='(unexpected status( code)?|status code|HTTP( status( code)?)?)[ :]+(429|502|503|504)([^0-9]|$)'
    transport_error='(rate limit exceeded|connection reset( by peer)?|temporary failure in name resolution|timed out|broken pipe)([^[:alnum:]]|$)'
    # Classify the leading cause, not status numbers quoted in error details.
    printf '%s\n' "$error_line" | grep -Eiq \
        "^(ERROR|Error|error):[[:space:]]*((server returned|stream disconnected before completion:)[[:space:]]+)?($status_error|$transport_error)"
}

run_codex() {
    local status=0 stderr_pid
    exec 3> >(tee "$attempt_stderr" >&2)
    stderr_pid=$!
    timeout --kill-after=30s "${remaining_seconds}s" \
        codex exec --profile loop --ephemeral -c "$git_permission" "$instructions" \
        < "$prompt_file" 2>&3 || status=$?
    exec 3>&-
    # Finish capturing stderr before inspecting its final error diagnostic.
    wait "$stderr_pid" || true
    return "$status"
}

instructions=$(printf '%s\n' \
        "The task source is $prompt_file; its current contents are attached as stdin." \
        'Work on exactly one highest-priority incomplete task.' \
        'Inspect the repository, implement the task, and run the relevant tests and checks.' \
        'Update the task source and any progress file it requires.' \
        'Before committing, spawn the configured reviewer subagent using the reviewer agent type and wait for its final decision.' \
        'If the reviewer finds blockers, fix them and rerun the same reviewer until it returns PASS.' \
        'If the reviewer cannot run or cannot return PASS, do not commit and do not report completion; explain the blocker.' \
        'Only after reviewer PASS, commit the completed work.' \
        'Do not ask the user questions. Make safe, scoped assumptions; if blocked, record why in the task source and end your response with <promise>BLOCKED</promise>.' \
        'Only if the entire task source is complete, end your response with <promise>COMPLETE</promise>.')

iterations_without_commit=0
for ((i = 1; i <= max_iterations; i++)); do
    printf 'Starting iteration %d of %d (timeout: %ds).\n' "$i" "$max_iterations" "$iteration_timeout" >&2
    SECONDS=0
    head_before=$(git rev-parse -q --verify HEAD || true)

    for ((attempt = 1; attempt <= 3; attempt++)); do
        remaining_seconds=$((iteration_timeout - SECONDS))
        if ((remaining_seconds <= 0)); then
            printf 'Iteration %d timed out.\n' "$i" >&2
            exit 124
        fi

        codex_status=0
        result=$(run_codex) || codex_status=$?
        printf '%s\n' "$result"

        if ((codex_status == 0)); then
            break
        fi
        if ((codex_status == 124 || codex_status == 137)); then
            printf 'Iteration %d timed out or was killed (status %d).\n' "$i" "$codex_status" >&2
            exit "$codex_status"
        fi
        if ((codex_status != 1 || attempt == 3)) || ! is_transient_error; then
            printf 'codex exited with status %d; stopping.\n' "$codex_status" >&2
            exit "$codex_status"
        fi

        if ((iteration_timeout - SECONDS <= 60)); then
            printf 'Not enough iteration time remains for a retry; stopping.\n' >&2
            exit "$codex_status"
        fi
        printf 'Transient Codex failure; retrying in 60s (attempt %d of 3).\n' "$((attempt + 1))" >&2
        sleep 60
    done

    if [[ $result == *'<promise>COMPLETE</promise>' ]]; then
        printf 'Task source complete after %d iteration(s).\n' "$i"
        exit 0
    fi
    if [[ $result == *'<promise>BLOCKED</promise>' ]]; then
        printf 'Blocked after %d iteration(s); see %s.\n' "$i" "$prompt_file" >&2
        exit 2
    fi

    if [[ $(git rev-parse -q --verify HEAD || true) == "$head_before" ]]; then
        iterations_without_commit=$((iterations_without_commit + 1))
        if ((iterations_without_commit >= 3)); then
            printf 'No new commit in 3 consecutive iterations; stopping. See %s.\n' "$prompt_file" >&2
            exit 3
        fi
    else
        iterations_without_commit=0
    fi
done

printf 'Stopped after %d iteration(s) without a completion signal.\n' "$max_iterations" >&2
exit 1
