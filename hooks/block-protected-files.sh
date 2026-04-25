#!/usr/bin/env bash
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Codex PreToolUse currently only protects Bash commands and is not a complete
# security boundary. This hook intentionally blocks any Bash command mentioning
# protected paths, including read-only commands such as cat, grep, head, or tail.
. "$SCRIPT_DIR/lib.sh"

PROTECTED_PATH_PATTERNS=(
    # .env
    '(^|[^[:alnum:]_-])\.env($|[^[:alnum:]_.-])'

    # .env.*
    '(^|[^[:alnum:]_-])\.env\.[^[:space:];&|]*'

    # *.pem
    '\.pem($|[^[:alnum:]_./-])'

    # *.key
    '\.key($|[^[:alnum:]_./-])'

    # id_rsa
    '(^|[^[:alnum:]_-])id_rsa($|[^[:alnum:]_-])'

    # id_ed25519
    '(^|[^[:alnum:]_-])id_ed25519($|[^[:alnum:]_-])'

    # kubeconfig
    '(^|[^[:alnum:]_-])kubeconfig($|[^[:alnum:]_-])'

    # terraform.tfstate
    '(^|[^[:alnum:]_-])terraform\.tfstate($|[^[:alnum:]_.-])'

    # terraform.tfvars
    '(^|[^[:alnum:]_-])terraform\.tfvars($|[^[:alnum:]_.-])'

    # *.tfvars
    '\.tfvars($|[^[:alnum:]_./-])'

    # secrets.yaml
    '(^|[^[:alnum:]_-])secrets\.yaml($|[^[:alnum:]_.-])'

    # secret.yaml
    '(^|[^[:alnum:]_-])secret\.yaml($|[^[:alnum:]_.-])'

    # .sops.yaml
    '(^|[^[:alnum:]_-])\.sops\.yaml($|[^[:alnum:]_.-])'

    # .aws/credentials
    '(^|[^[:alnum:]_.-])\.aws/credentials($|[^[:alnum:]_./-])'

    # .kube/config
    '(^|[^[:alnum:]_.-])\.kube/config($|[^[:alnum:]_./-])'

    # SSH private config and trust stores
    '(^|[^[:alnum:]_-])\.ssh($|/|[^[:alnum:]_.-])'
    '(^|[^[:alnum:]_-])authorized_keys($|[^[:alnum:]_.-])'
    '(^|[^[:alnum:]_-])known_hosts($|[^[:alnum:]_.-])'

    # GPG, password-store, and age identities
    '(^|[^[:alnum:]_-])\.gnupg($|/|[^[:alnum:]_.-])'
    '(^|[^[:alnum:]_-])\.password-store($|/|[^[:alnum:]_.-])'
    '(^|[^[:alnum:]_-])age/keys\.txt($|[^[:alnum:]_./-])'

    # Common package, registry, and Docker credentials
    '(^|[^[:alnum:]_-])\.netrc($|[^[:alnum:]_.-])'
    '(^|[^[:alnum:]_-])\.npmrc($|[^[:alnum:]_.-])'
    '(^|[^[:alnum:]_-])\.pypirc($|[^[:alnum:]_.-])'
    '(^|[^[:alnum:]_.-])\.gem/credentials($|[^[:alnum:]_./-])'
    '(^|[^[:alnum:]_.-])\.docker/config\.json($|[^[:alnum:]_./-])'

    # GitHub, GitLab, and cloud CLI credentials/config
    '(^|[^[:alnum:]_.-])\.config/gh/hosts\.yml($|[^[:alnum:]_./-])'
    '(^|[^[:alnum:]_.-])\.config/glab-cli($|/|[^[:alnum:]_./-])'
    '(^|[^[:alnum:]_.-])\.aws/config($|[^[:alnum:]_./-])'
    '(^|[^[:alnum:]_.-])\.azure($|/|[^[:alnum:]_./-])'
    '(^|[^[:alnum:]_.-])\.config/gcloud($|/|[^[:alnum:]_./-])'

    # Kubernetes and Terraform local state/config
    '(^|[^[:alnum:]_-])\.kube($|/|[^[:alnum:]_.-])'
    '(^|[^[:alnum:]_.-])\.terraform/terraform\.tfstate($|[^[:alnum:]_./-])'
    '(^|[^[:alnum:]_-])\.terraformrc($|[^[:alnum:]_.-])'
    '(^|[^[:alnum:]_-])terraform\.tfstate\.backup($|[^[:alnum:]_.-])'
    '(^|[^[:alnum:]_-])\.terraform\.lock\.hcl($|[^[:alnum:]_.-])'
    '(^|[^[:alnum:]_.-])\.terraform($|/|[^[:alnum:]_./-])'
    '(^|[^[:alnum:]_.-])\.tofu($|/|[^[:alnum:]_./-])'

    # VMware, Ansible, and automation credentials/config
    '(^|[^[:alnum:]_.-])\.vmware($|/|[^[:alnum:]_./-])'
    '(^|[^[:alnum:]_-])govc\.env($|[^[:alnum:]_.-])'
    '(^|[^[:alnum:]_-])ansible\.cfg($|[^[:alnum:]_.-])'
    '(^|[^[:alnum:]_-])vault\.ya?ml($|[^[:alnum:]_.-])'
    '(^|[^[:alnum:]_-])\.vault_pass($|[^[:alnum:]_.-])'
    '(^|[^[:alnum:]_-])vault-password-file($|[^[:alnum:]_.-])'

    # OpenShift install and cluster secrets
    '(^|[^[:alnum:]_-])install-config\.yaml($|[^[:alnum:]_.-])'
    '(^|[^[:alnum:]_-])kubeadmin-password($|[^[:alnum:]_.-])'
    '(^|[^[:alnum:]_-])pull-secret($|[^[:alnum:]_.-])'
    '(^|[^[:alnum:]_-])auth/kubeconfig($|[^[:alnum:]_./-])'
    '(^|[^[:alnum:]_-])auth/kubeadmin-password($|[^[:alnum:]_./-])'
    '(^|[^[:alnum:]_-])metadata\.json($|[^[:alnum:]_.-])'

    # Platform and monitoring credentials/config
    '(^|[^[:alnum:]_-])grafana\.ini($|[^[:alnum:]_.-])'
    '(^|[^[:alnum:]_-])prometheus\.yml($|[^[:alnum:]_.-])'
    '(^|[^[:alnum:]_-])alertmanager\.yml($|[^[:alnum:]_.-])'
    '(^|[^[:alnum:]_-])htpasswd($|[^[:alnum:]_.-])'
    '(^|[^[:alnum:]_-])ca\.crt($|[^[:alnum:]_.-])'
    '(^|[^[:alnum:]_-])tls\.crt($|[^[:alnum:]_.-])'
    '(^|[^[:alnum:]_-])tls\.key($|[^[:alnum:]_.-])'

    # System auth and host identity
    '(^|[^[:alnum:]_.-])/etc/shadow($|[^[:alnum:]_./-])'
    '(^|[^[:alnum:]_.-])/etc/sudoers($|[^[:alnum:]_./-])'
    '(^|[^[:alnum:]_.-])/etc/ssh/ssh_host_[^[:space:];&|]*_key($|[^[:alnum:]_./-])'
    '(^|[^[:alnum:]_.-])/etc/NetworkManager/system-connections($|/|[^[:alnum:]_./-])'
    '(^|[^[:alnum:]_.-])/etc/hosts($|[^[:alnum:]_./-])'
    '(^|[^[:alnum:]_.-])/etc/resolv\.conf($|[^[:alnum:]_./-])'
    '(^|[^[:alnum:]_.-])/etc/sysconfig/network-scripts($|/|[^[:alnum:]_./-])'

    # Codex auth
    '(^|[^[:alnum:]_.-])\.codex/auth\.json($|[^[:alnum:]_./-])'

    # Shell startup files that can change future command behavior
    '(^|[^[:alnum:]_-])\.bashrc($|[^[:alnum:]_.-])'
    '(^|[^[:alnum:]_-])\.zshrc($|[^[:alnum:]_.-])'
    '(^|[^[:alnum:]_-])\.profile($|[^[:alnum:]_.-])'
    '(^|[^[:alnum:]_-])\.bash_profile($|[^[:alnum:]_.-])'
    '(^|[^[:alnum:]_-])\.zprofile($|[^[:alnum:]_.-])'

    # Git config and executable hook injection points
    '(^|[^[:alnum:]_.-])\.git/config($|[^[:alnum:]_./-])'
    '(^|[^[:alnum:]_.-])\.git/hooks($|/|[^[:alnum:]_./-])'

    # User systemd units can create persistent background execution
    '(^|[^[:alnum:]_.-])\.config/systemd($|/|[^[:alnum:]_./-])'
)

init_hook_input || exit 0

if command_matches_patterns "${PROTECTED_PATH_PATTERNS[@]}"; then
    reason="Blocked by Codex hook: Bash command mentions a protected file or path.
Command: $(command_for_reason)"
    append_blocked_log "$reason" "embedded-protected-path-patterns" "$MATCHED_PATTERN"
    deny_pre_tool_use "$reason"
fi
