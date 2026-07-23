#!/usr/bin/env bash
set -euo pipefail

usage() {
    printf 'Usage: %s <prompt-or-prd-file> <max-iterations>\n' "$0" >&2
}

if [[ $# -ne 2 ]]; then
    usage
    exit 64
fi

prompt_file=$1
max_iterations=$2

if [[ ! -f $prompt_file ]]; then
    printf 'Prompt/PRD file not found: %s\n' "$prompt_file" >&2
    exit 66
fi

if [[ ! $max_iterations =~ ^[1-9][0-9]*$ ]]; then
    printf 'Max iterations must be a positive integer.\n' >&2
    exit 64
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

for ((i = 1; i <= max_iterations; i++)); do
    printf 'Starting iteration %d of %d.\n' "$i" "$max_iterations" >&2

    instructions=$(printf '%s\n' \
        "The task source is $prompt_file; its current contents are attached as stdin." \
        'Work on exactly one highest-priority incomplete task.' \
        'Inspect the repository, implement the task, and run the relevant tests and checks.' \
        'Update the task source and any progress file it requires.' \
        'Before committing, spawn the configured reviewer subagent using the reviewer agent type and wait for its final decision.' \
        'If the reviewer finds blockers, fix them and rerun the same reviewer until it returns PASS.' \
        'If the reviewer cannot run or cannot return PASS, do not commit and do not report completion; explain the blocker.' \
        'Only after reviewer PASS, commit the completed work.' \
        'Do not ask the user questions. Make safe, scoped assumptions; if blocked, explain the blocker.' \
        'Only if the entire task source is complete, end your response with <promise>COMPLETE</promise>.')

    result=$(codex exec --profile loop --ephemeral "$instructions" < "$prompt_file")

    printf '%s\n' "$result"

    if [[ $result == *'<promise>COMPLETE</promise>' ]]; then
        printf 'Task source complete after %d iteration(s).\n' "$i"
        exit 0
    fi
done

printf 'Stopped after %d iteration(s) without a completion signal.\n' "$max_iterations" >&2
exit 1
