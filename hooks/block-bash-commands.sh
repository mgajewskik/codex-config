#!/usr/bin/env bash
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Codex PreToolUse currently only protects Bash commands and is not a complete
# security boundary. Treat this as a guardrail for obvious dangerous commands.
. "$SCRIPT_DIR/lib.sh"

BLOCKED_COMMAND_PATTERNS=(
    # Security-sensitive deny rules are contains-style regexes over the full
    # normalized command.

    # Privilege escalation and identity switching
    '(^|[^[:alnum:]_.-])(sudoedit|sudo|doas|pkexec|su|runuser)($|[^[:alnum:]_.-])'

    # Host power-state and rescue/emergency transitions
    '(^|[^[:alnum:]_.-])(shutdown|reboot|halt|poweroff)($|[^[:alnum:]_.-])'
    '(^|[^[:alnum:]_.-])(init|telinit)[[:space:]]+(0|6)($|[^[:alnum:]_.-])'
    '(^|[^[:alnum:]_.-])systemctl([[:space:]]+--?[[:alnum:]][[:alnum:]-]*(=([^[:space:];&|]+))?)*[[:space:]]+(reboot|poweroff|halt|kexec|suspend|hibernate|hybrid-sleep|suspend-then-hibernate|rescue|emergency)($|[^[:alnum:]_.-])'
    '(^|[^[:alnum:]_.-])systemctl([[:space:]]+--?[[:alnum:]][[:alnum:]-]*(=([^[:space:];&|]+))?)*[[:space:]]+isolate[[:space:]]+(reboot|poweroff|halt|kexec|suspend|hibernate|hybrid-sleep|suspend-then-hibernate|rescue|emergency)\.target($|[^[:alnum:]_.-])'
    '(^|[^[:alnum:]_.-])loginctl([[:space:]]+--?[[:alnum:]][[:alnum:]-]*(=([^[:space:];&|]+))?)*[[:space:]]+(reboot|poweroff|halt|suspend|hibernate|hybrid-sleep|suspend-then-hibernate|terminate-session|kill-session|terminate-user|kill-user|lock-session|unlock-session|lock-sessions|unlock-sessions)($|[^[:alnum:]_.-])'

    # Package managers and install surfaces
    '(^|[^[:alnum:]_.-])(pacman|yay|paru|trizen|pikaur|aurman|pakku|makepkg|apt|apt-get|dpkg|yum|dnf|rpm|snap|flatpak|brew|rtx|asdf|easy_install|npx|bunx)($|[^[:alnum:]_.-])'
    '(^|[^[:alnum:]_.-])(pip|npm|cargo|gem)[[:space:]]+(install|uninstall)($|[^[:alnum:]_.-])'
    '(^|[^[:alnum:]_.-])go[[:space:]]+(install|get)($|[^[:alnum:]_.-])'
    '(^|[^[:alnum:]_.-])mise[[:space:]]+install($|[^[:alnum:]_.-])'
    '(^|[^[:alnum:]_.-])(conda|mamba|micromamba)[[:space:]]+install($|[^[:alnum:]_.-])'
    '(^|[^[:alnum:]_.-])(python|python3)[[:space:]]+-m[[:space:]]+pip[[:space:]]+(install|uninstall)($|[^[:alnum:]_.-])'
    '(^|[^[:alnum:]_.-])(yarn|pnpm)[[:space:]]+dlx($|[^[:alnum:]_.-])'
    '(^|[^[:alnum:]_.-])deno[[:space:]]+run[^;&|]*--allow-all($|[^[:alnum:]_.-])'

    # Interpreter -c/-e/--eval one-liners with dangerous payloads. These bypass
    # every command-name hook above; bwrap still blocks local writes outside
    # cwd, but remote-state mutation via SDKs and raw sockets succeeds. Match
    # interpreter invocation followed by an eval flag, with payload mentioning
    # process spawning, cloud/infra SDKs, HTTP mutations, raw sockets, or
    # backticked destructive commands.
    '(^|[^[:alnum:]_.-])(python|python3|perl|ruby|node|deno|php|lua)[[:space:]]+(-c|-e|-E|--eval|eval|-r)[[:space:]]+.*(subprocess|os\.system|os\.popen|os\.exec|os\.fork|child_process|spawn[Ss]ync|Deno\.(run|Command)|Open3|IO\.popen|Process\.spawn|shell_exec|passthru|popen[[:space:]]*\(|system[[:space:]]*\(|exec[[:space:]]*\()'
    '(^|[^[:alnum:]_.-])(python|python3|perl|ruby|node|deno|php)[[:space:]]+(-c|-e|-E|--eval|eval|-r)[[:space:]]+.*(boto3|botocore|kubernetes\.client|paramiko|fabric|hvac|google\.cloud|azure\.identity|azure\.mgmt)'
    '(^|[^[:alnum:]_.-])(python|python3|perl|ruby|node|deno|php)[[:space:]]+(-c|-e|-E|--eval|eval|-r)[[:space:]]+.*(requests|httpx|urllib3?|axios|http\.client)\.(delete|post|put|patch|Delete|Post|Put|Patch|DELETE|POST|PUT|PATCH)'
    '(^|[^[:alnum:]_.-])(python|python3|perl|ruby|node|deno|php)[[:space:]]+(-c|-e|-E|--eval|eval|-r)[[:space:]]+.*(socket\.(socket|connect|create_connection)|TCPSocket|Net::TCP|tls\.connect)'
    '(^|[^[:alnum:]_.-])(perl|ruby)[[:space:]]+(-e|-E)[[:space:]]+.*`[^`]*(rm[[:space:]]|kubectl|terraform|aws[[:space:]]|gcloud|helm[[:space:]]|sudo[[:space:]]|curl[[:space:]]|wget[[:space:]]|systemctl|reboot|shutdown)'

    # Environment and shell introspection
    '(^|[^[:alnum:]_.-])(env|printenv|export|set|declare|compgen|history|fc)($|[^[:alnum:]_.-])'

    # Container, cluster, and infra state read or mutation surfaces
    '(^|[^[:alnum:]_.-])docker[[:space:]]+run[^;&|]*(--privileged|--pid=host|--net=host)($|[^[:alnum:]_.-])'
    '(^|[^[:alnum:]_.-])docker-compose[[:space:]]+config($|[^[:alnum:]_.-])'
    '(^|[^[:alnum:]_.-])(crictl)($|[^[:alnum:]_.-])'
    '(^|[^[:alnum:]_.-])(kubectl|k)([^;&|]*[[:space:]])get[[:space:]]+secret($|[^[:alnum:]_.-])'
    '(^|[^[:alnum:]_.-])(kubectl|k)([^;&|]*[[:space:]])describe[[:space:]]+secret($|[^[:alnum:]_.-])'
    '(^|[^[:alnum:]_.-])(kubectl|k)([^;&|]*[[:space:]])apply[^;&|]*--force($|[^[:alnum:]_.-])'

    # kubectl/oc apply or create from a remote URL or stdin manifest. Plain
    # kubectl apply -f URL is not covered by the --force pattern above and would
    # let an attacker apply a hostile manifest into the active cluster.
    '(^|[^[:alnum:]_.-])(kubectl|k|oc)[^;&|]*[[:space:]]+(apply|create|replace)[^;&|]*[[:space:]]+(-f|--filename)[[:space:]]+https?://'
    '(^|[^[:alnum:]_.-])(kubectl|k|oc)[^;&|]*[[:space:]]+(apply|create|replace)[^;&|]*[[:space:]]+(-f|--filename)[[:space:]]+-($|[[:space:]])'

    '(^|[^[:alnum:]_.-])helm[[:space:]]+delete($|[^[:alnum:]_.-])'
    '(^|[^[:alnum:]_.-])(terraform|tf|tofu)([^;&|]*[[:space:]])(output|show|state)($|[^[:alnum:]_.-])'
    '(^|[^[:alnum:]_.-])ansible-vault($|[^[:alnum:]_.-])'
    '(^|[^[:alnum:]_.-])pulumi[[:space:]]+destroy($|[^[:alnum:]_.-])'

    # Recon, offensive tooling, packet capture, and process introspection
    '(^|[^[:alnum:]_.-])(nmap|masscan|nikto|metasploit|msfconsole|msfvenom|sqlmap|hydra|john|hashcat|aircrack|wireshark|tcpdump|tshark|ettercap|bettercap|responder|empire|covenant|ngrep|mitm|sslstrip|dsniff|arpspoof|burpsuite|zap|gobuster|dirb|dirbuster|wfuzz|ffuf|strace|ltrace|gdb|ptrace|gcore|pmap)($|[^[:alnum:]_.-])'

    # Destructive system, boot, account, permission, clipboard, and shell-escape surfaces
    '(^|[^[:alnum:]_.-])(dd|mkfs|fdisk|parted|shred|wipe|scrub|badblocks|shutdown|reboot|halt|poweroff|grub|efibootmgr|kexec|kdump|dracut|mkinitcpio|update-initramfs|insmod|rmmod|modprobe|sysctl|xclip|xsel|pbpaste|wl-paste|pbcopy|wl-copy|passwd|useradd|userdel|usermod|groupadd|groupdel|adduser|deluser)($|[^[:alnum:]_.-])'
    '(^|[^[:alnum:]_.-])ln[[:space:]]+-sf($|[^[:alnum:]_.-])'
    '(^|[^[:alnum:]_.-])systemctl[[:space:]]+stop[[:space:]]+(ssh|network)($|[^[:alnum:]_.-])'
    '(^|[^[:alnum:]_.-])systemctl[[:space:]]+(mask|disable)($|[^[:alnum:]_.-])'
    '(^|[^[:alnum:]_.-])(killall|pkill)[[:space:]]+ssh($|[^[:alnum:]_.-])'
    '(^|[^[:alnum:]_.-])ruby[[:space:]]+-rsocket($|[^[:alnum:]_.-])'
    '(^|[^[:alnum:]_.-])(nc|ncat)[[:space:]]+-e($|[^[:alnum:]_.-])'
    '(^|[^[:alnum:]_.-])nc[[:space:]]+(-c|-l)($|[^[:alnum:]_.-])'
    '(^|[^[:alnum:]_.-])netcat[[:space:]]+-l($|[^[:alnum:]_.-])'
    '(^|[^[:alnum:]_.-])ssh[[:space:]]+-R($|[^[:alnum:]_.-])'
    '(^|[^[:alnum:]_.-])socat($|[^[:alnum:]_.-])'
    '(^|[^[:alnum:]_.-])chmod[[:space:]]+(-R[[:space:]]+)?(777|666)($|[^[:alnum:]_.-])'
    '(^|[^[:alnum:]_.-])chown[[:space:]]+(-R|root(:[^[:space:];&|]+)?)($|[^[:alnum:]_.-])'
    '(^|[^[:alnum:]_.-])chgrp[[:space:]]+-R($|[^[:alnum:]_.-])'
    '(^|[^[:alnum:]_.-])function[[:space:]]+sudo($|[^[:alnum:]_.-])'
    '(^|[^[:alnum:]_.-])nano[[:space:]]+-s($|[^[:alnum:]_.-])'

    # rm -rf /
    '(^|[^[:alnum:]_.-])rm[[:space:]]+-[^[:space:]]*r[^[:space:]]*f[^[:space:]]*[[:space:]]+/($|[^[:alnum:]_.-])'

    # rm -rf ~
    '(^|[^[:alnum:]_.-])rm[[:space:]]+-[^[:space:]]*r[^[:space:]]*f[^[:space:]]*[[:space:]]+~($|[^[:alnum:]_.-])'

    # sudo rm -rf
    '(^|[^[:alnum:]_.-])sudo[[:space:]]+rm[[:space:]]+-[^[:space:]]*r[^[:space:]]*f[^[:space:]]*'

    # git reset --hard, including extra reset flags before --hard
    '(^|[^[:alnum:]_.-])git[[:space:]]+reset([^;&|]*[[:space:]])--hard($|[^[:alnum:]_.-])'

    # git clean -fd/-f -d
    '(^|[^[:alnum:]_.-])git[[:space:]]+clean([^;&|]*[[:space:]])-[^[:space:]]*f[^[:space:]]*d[^[:space:]]*($|[^[:alnum:]_.-])'
    '(^|[^[:alnum:]_.-])git[[:space:]]+clean([^;&|]*[[:space:]])-[^[:space:]]*f[^;&|]*[[:space:]]+-[^[:space:]]*d[^[:space:]]*($|[^[:alnum:]_.-])'

    # git push --force/-f/--force-with-lease
    '(^|[^[:alnum:]_.-])git[[:space:]]+push([^;&|]*[[:space:]])(--force($|[^[:alnum:]_.-])|--force-with-lease($|[^[:alnum:]_.-])|-f($|[^[:alnum:]_.-]))'

    # curl ... | bash
    '(^|[^[:alnum:]_.-])curl([^|]*)\|[[:space:]]*(sudo[[:space:]]+)?bash($|[^[:alnum:]_.-])'

    # wget ... | sh
    '(^|[^[:alnum:]_.-])wget([^|]*)\|[[:space:]]*(sudo[[:space:]]+)?sh($|[^[:alnum:]_.-])'

    # bash/sh -c "$(curl ...)" or "$(wget ...)"
    '(^|[^[:alnum:]_.-])(bash|sh)[[:space:]]+-c[^;&|]*\$\([^)]*(curl|wget)'

    # source <(curl ...) or . <(wget ...)
    '(^|[^[:alnum:]_.-])(source|\.)[[:space:]]+<\([^)]*(curl|wget)'

    # download, chmod executable, then run in one shell line
    '(^|[^[:alnum:]_.-])(curl|wget)[^;&|]*(&&|;)[[:space:]]*chmod[[:space:]]+[^;&|]*\+x[^;&|]*(&&|;)[[:space:]]*(\./|/tmp/|/var/tmp/|bash[[:space:]]|sh[[:space:]])'

    # git push --mirror
    '(^|[^[:alnum:]_.-])git[[:space:]]+push([^;&|]*[[:space:]])--mirror($|[^[:alnum:]_.-])'

    # git push origin --delete/-d branch
    '(^|[^[:alnum:]_.-])git[[:space:]]+push([^;&|]*[[:space:]])(--delete|-d)($|[^[:alnum:]_.-])'

    # git push origin :branch
    '(^|[^[:alnum:]_.-])git[[:space:]]+push[^;&|]*[[:space:]]:[^[:space:];&|]+'

    # git push +refs/...
    '(^|[^[:alnum:]_.-])git[[:space:]]+push[^;&|]*\+refs/'

    # Terraform/OpenTofu destructive or state-mutating operations
    '(^|[^[:alnum:]_.-])(terraform|tofu|tf)([^;&|]*[[:space:]])destroy($|[^[:alnum:]_.-])'
    '(^|[^[:alnum:]_.-])(terraform|tofu|tf)([^;&|]*[[:space:]])apply([^;&|]*[[:space:]])--?auto-approve($|[^[:alnum:]_.-])'
    '(^|[^[:alnum:]_.-])(terraform|tofu|tf)([^;&|]*[[:space:]])state[[:space:]]+(rm|mv|push)($|[^[:alnum:]_.-])'
    '(^|[^[:alnum:]_.-])(terraform|tofu|tf)([^;&|]*[[:space:]])import[^;&|]*($|[^[:alnum:]_.-])'
    '(^|[^[:alnum:]_.-])(terraform|tofu|tf)([^;&|]*[[:space:]])force-unlock[^;&|]*($|[^[:alnum:]_.-])'
    '(^|[^[:alnum:]_.-])(terraform|tofu|tf)([^;&|]*[[:space:]])workspace[[:space:]]+delete($|[^[:alnum:]_.-])'

    # kubectl/k delete namespace
    '(^|[^[:alnum:]_.-])(kubectl|k)[^;&|]*[[:space:]]+delete[[:space:]]+(namespace|ns)($|[^[:alnum:]_.-])'

    # kubectl/k delete crd
    '(^|[^[:alnum:]_.-])(kubectl|k)[^;&|]*[[:space:]]+delete[[:space:]]+crd($|[^[:alnum:]_.-])'

    # helm uninstall
    '(^|[^[:alnum:]_.-])helm[[:space:]]+uninstall($|[^[:alnum:]_.-])'

    # helm install/upgrade from a remote OCI/HTTP chart — bypasses local
    # vetting and pulls arbitrary chart code into the cluster.
    '(^|[^[:alnum:]_.-])helm[[:space:]]+(install|upgrade)[[:space:]]+[^[:space:];&|]+[[:space:]]+(oci://|https?://)'

    # ansible-playbook against production inventory
    '(^|[^[:alnum:]_.-])ansible-playbook([^;&|]*[[:space:]])(-i|--inventory)(=|[[:space:]])[^;&|[:space:]]*prod(uction)?[^;&|[:space:]]*'

    # Ansible ad-hoc destructive modules or privileged broad/prod playbook runs
    '(^|[^[:alnum:]_.-])ansible[[:space:]][^;&|]*[[:space:]]+-m[[:space:]]+(shell|command|raw)[^;&|]*[[:space:]]+-a[[:space:]]+[^;&|]*(rm[[:space:]]+-rf|mkfs|shutdown|reboot|systemctl[[:space:]]+(stop|disable|mask))'
    '(^|[^[:alnum:]_.-])ansible-playbook[^;&|]*(--become|-b)[^;&|]*(-i|--inventory)(=|[[:space:]])[^;&|[:space:]]*(prod|production|all)[^;&|[:space:]]*'
    '(^|[^[:alnum:]_.-])ansible-playbook[^;&|]*(--extra-vars|-e)[^;&|]*(state=absent|delete=true|destroy=true|purge=true)'

    # qm destroy
    '(^|[^[:alnum:]_.-])qm[[:space:]]+destroy($|[^[:alnum:]_.-])'

    # pvesh delete
    '(^|[^[:alnum:]_.-])pvesh[[:space:]]+delete($|[^[:alnum:]_.-])'

    # Proxmox destructive VM/container/storage/cluster operations
    '(^|[^[:alnum:]_.-])qm[[:space:]]+(stop|shutdown|reset|reboot|rollback|unlink|disk[[:space:]]+unlink)($|[^[:alnum:]_.-])'
    '(^|[^[:alnum:]_.-])pct[[:space:]]+(destroy|stop|shutdown|reboot|restore)($|[^[:alnum:]_.-])'
    '(^|[^[:alnum:]_.-])pvesm[[:space:]]+(free|remove|delete)($|[^[:alnum:]_.-])'
    '(^|[^[:alnum:]_.-])ha-manager[[:space:]]+(remove|disable|migrate|set)[^;&|]*(--state[[:space:]]+disabled|disabled)'
    '(^|[^[:alnum:]_.-])pvecm[[:space:]]+(delnode|expected)($|[^[:alnum:]_.-])'

    # psql -c "DROP ..." or "TRUNCATE ..."
    '(^|[^[:alnum:]_.-])psql([^;&|]*[[:space:]])-c[[:space:]]+[^;&|]*([Dd][Rr][Oo][Pp]|[Tt][Rr][Uu][Nn][Cc][Aa][Tt][Ee])'

    # mysql -e "DROP ..." or "TRUNCATE ..."
    '(^|[^[:alnum:]_.-])mysql([^;&|]*[[:space:]])-e[[:space:]]+[^;&|]*([Dd][Rr][Oo][Pp]|[Tt][Rr][Uu][Nn][Cc][Aa][Tt][Ee])'

    # sqlite3 database "DROP ..." or "TRUNCATE ..."
    '(^|[^[:alnum:]_.-])sqlite3[[:space:]][^;&|]*([Dd][Rr][Oo][Pp]|[Tt][Rr][Uu][Nn][Cc][Aa][Tt][Ee])'

    # redis destructive flushes
    '(^|[^[:alnum:]_.-])redis-cli[^;&|]*([Ff][Ll][Uu][Ss][Hh][Aa][Ll][Ll]|[Ff][Ll][Uu][Ss][Hh][Dd][Bb])($|[^[:alnum:]_.-])'

    # AWS delete/terminate operations
    '(^|[^[:alnum:]_.-])aws[[:space:]][^;&|]*(delete-[^[:space:];&|]+|terminate-instances)($|[^[:alnum:]_.-])'

    # Cloud CLI delete operations
    '(^|[^[:alnum:]_.-])gcloud[[:space:]][^;&|]*[[:space:]]delete($|[^[:alnum:]_.-])'
    '(^|[^[:alnum:]_.-])az[[:space:]][^;&|]*[[:space:]]delete($|[^[:alnum:]_.-])'
    '(^|[^[:alnum:]_.-])doctl[[:space:]][^;&|]*[[:space:]]delete($|[^[:alnum:]_.-])'

    # GitHub repository deletion
    '(^|[^[:alnum:]_.-])gh[[:space:]]+repo[[:space:]]+delete($|[^[:alnum:]_.-])'

    # GitHub secret/release/repo-visibility ops — secret rotation to attacker
    # repo, release publishing, or making a private repo public.
    '(^|[^[:alnum:]_.-])gh[[:space:]]+secret[[:space:]]+(set|delete)($|[^[:alnum:]_.-])'
    '(^|[^[:alnum:]_.-])gh[[:space:]]+release[[:space:]]+(create|delete|edit)($|[^[:alnum:]_.-])'
    '(^|[^[:alnum:]_.-])gh[[:space:]]+repo[[:space:]]+create[^;&|]*--public'
    '(^|[^[:alnum:]_.-])gh[[:space:]]+repo[[:space:]]+edit[^;&|]*--visibility[[:space:]]+public'

    # Kubernetes destructive broad operations
    '(^|[^[:alnum:]_.-])(kubectl|k)[^;&|]*[[:space:]]+delete[[:space:]]+all([^;&|]*[[:space:]])--all($|[^[:alnum:]_.-])'
    '(^|[^[:alnum:]_.-])(kubectl|k)[^;&|]*[[:space:]]+delete[[:space:]]+(-f|--filename|-k|--kustomize)($|[^[:alnum:]_.-])'
    '(^|[^[:alnum:]_.-])(kubectl|k)[^;&|]*[[:space:]]+replace([^;&|]*[[:space:]])--force($|[^[:alnum:]_.-])'
    '(^|[^[:alnum:]_.-])(kubectl|k)[^;&|]*[[:space:]]+scale[^;&|]*--replicas=0($|[^[:alnum:]_.-])'
    '(^|[^[:alnum:]_.-])(kubectl|k)[^;&|]*[[:space:]]+create[[:space:]]+(clusterrolebinding|rolebinding)[^;&|]*(cluster-admin|system:masters)'
    '(^|[^[:alnum:]_.-])(kubectl|k)[^;&|]*[[:space:]]+auth[[:space:]]+reconcile[^;&|]*-f'
    '(^|[^[:alnum:]_.-])(kubectl|k)[^;&|]*[[:space:]]+patch[[:space:]]+(clusterrole|clusterrolebinding|role|rolebinding|validatingwebhookconfiguration|mutatingwebhookconfiguration|apiservice|crd)'
    '(^|[^[:alnum:]_.-])(kubectl|k)[^;&|]*[[:space:]]+taint[[:space:]]+nodes?[^;&|]*NoSchedule'
    '(^|[^[:alnum:]_.-])(kubectl|k)[^;&|]*[[:space:]]+drain($|[^[:alnum:]_.-])'

    # OpenShift/OKD destructive or privilege-escalating operations
    '(^|[^[:alnum:]_.-])oc[[:space:]]+delete[[:space:]]+(project|namespace|ns|crd|clusteroperator|co|machine|machineset|machineconfig|machineconfigpool|mcp)($|[^[:alnum:]_.-])'
    '(^|[^[:alnum:]_.-])oc[[:space:]]+delete[[:space:]]+(-f|--filename|-k|--kustomize)($|[^[:alnum:]_.-])'
    '(^|[^[:alnum:]_.-])oc[[:space:]]+adm[[:space:]]+policy[[:space:]]+add-cluster-role-to-user[[:space:]]+cluster-admin'
    '(^|[^[:alnum:]_.-])oc[[:space:]]+adm[[:space:]]+policy[[:space:]]+add-scc-to-user[[:space:]]+privileged'
    '(^|[^[:alnum:]_.-])oc[[:space:]]+adm[[:space:]]+(drain|cordon|uncordon|upgrade)($|[^[:alnum:]_.-])'
    '(^|[^[:alnum:]_.-])oc[[:space:]]+patch[[:space:]]+(oauth|authentication|ingress|proxy|apiserver|image|operatorhub|clusteroperator|co)[^;&|]*--type'

    # Forceful Helm upgrades
    '(^|[^[:alnum:]_.-])helm[[:space:]]+upgrade[^;&|]*--force($|[^[:alnum:]_.-])'

    # Arch/RHEL package and bootloader risk
    '(^|[^[:alnum:]_.-])pacman[[:space:]]+(-Rdd|(-R|--remove)[^;&|]*(--nodeps|-dd))'
    '(^|[^[:alnum:]_.-])dnf[[:space:]]+(remove|erase)[^;&|]*(kernel|systemd|glibc|openssl|NetworkManager|selinux-policy)'
    '(^|[^[:alnum:]_.-])rpm[[:space:]]+(-e|--erase)[^;&|]*(--nodeps|kernel|systemd|glibc|openssl|selinux-policy)'
    '(^|[^[:alnum:]_.-])grub-(install|mkconfig)($|[^[:alnum:]_.-])'
    '(^|[^[:alnum:]_.-])bootctl[[:space:]]+(install|remove|update)($|[^[:alnum:]_.-])'

    # SELinux weakening or broad relabeling
    '(^|[^[:alnum:]_.-])setenforce[[:space:]]+0($|[^[:alnum:]_.-])'
    '(^|[^[:alnum:]_.-])semanage[[:space:]]+permissive[[:space:]]+-a'
    '(^|[^[:alnum:]_.-])semodule[[:space:]]+-r'
    '(^|[^[:alnum:]_.-])sed[^;&|]*SELINUX=disabled[^;&|]*/etc/selinux/config'
    '(^|[^[:alnum:]_.-])chcon[[:space:]]+-R($|[^[:alnum:]_.-])'

    # Storage, virtualization, and on-prem blast-radius commands
    '(^|[^[:alnum:]_.-])govc[[:space:]]+(vm\.destroy|vm\.power[[:space:]].*-off|vm\.unregister|datastore\.rm|object\.destroy)($|[^[:alnum:]_.-])'
    '(^|[^[:alnum:]_.-])govc[[:space:]]+(permissions\.set|role\.create|role\.remove|role\.update)($|[^[:alnum:]_.-])'
    '(^|[^[:alnum:]_.-])esxcli[[:space:]]+system[[:space:]]+(shutdown|maintenanceMode)[^;&|]*(--enable|--reboot|--poweroff|true)'
    '(^|[^[:alnum:]_.-])esxcli[[:space:]]+network[[:space:]]+firewall[[:space:]]+set[^;&|]*(--enabled[=[:space:]]*false|-e[=[:space:]]*false)'
    '(^|[^[:alnum:]_.-])esxcli[[:space:]]+storage[^;&|]*(remove|delete|detach|unmount)'
    '(^|[^[:alnum:]_.-])vim-cmd[[:space:]]+vmsvc/(power\.off|destroy|unregister)($|[^[:alnum:]_.-])'
    '(^|[^[:alnum:]_.-])virsh[[:space:]]+(destroy|undefine|vol-delete|pool-destroy)($|[^[:alnum:]_.-])'
    '(^|[^[:alnum:]_.-])ipmitool[^;&|]*(power[[:space:]]+(off|cycle|reset)|chassis[[:space:]]+power[[:space:]]+(off|cycle|reset))'
    '(^|[^[:alnum:]_.-])ceph[[:space:]]+osd[[:space:]]+(destroy|purge|out|rm)($|[^[:alnum:]_.-])'
    '(^|[^[:alnum:]_.-])zfs[[:space:]]+destroy($|[^[:alnum:]_.-])'
    '(^|[^[:alnum:]_.-])btrfs[[:space:]]+subvolume[[:space:]]+delete($|[^[:alnum:]_.-])'
    '(^|[^[:alnum:]_.-])lvremove($|[^[:alnum:]_.-])'
    '(^|[^[:alnum:]_.-])vgremove($|[^[:alnum:]_.-])'
    '(^|[^[:alnum:]_.-])pvremove($|[^[:alnum:]_.-])'
    '(^|[^[:alnum:]_.-])mdadm[^;&|]*(--stop|--zero-superblock)'

    # Container runtime destructive cleanup
    '(^|[^[:alnum:]_.-])(docker|podman|nerdctl)[[:space:]]+system[[:space:]]+prune[^;&|]*(-a|--all)'
    '(^|[^[:alnum:]_.-])(docker|podman|nerdctl)[[:space:]]+(rm|rmi)[^;&|]*(-f|--force)'
    '(^|[^[:alnum:]_.-])crictl[[:space:]]+(rm|rmi|rmp|stopp)($|[^[:alnum:]_.-])'

    # Generic HTTP mutation methods via curl/wget — DELETE/PUT/PATCH on any
    # endpoint are the most direct way to mutate remote state without going
    # through a wrapped CLI. Allow GET/HEAD/POST since they are common for
    # reads and form submissions; agents should use the dedicated CLI for
    # mutations so we have CLI-specific deny coverage.
    '(^|[^[:alnum:]_.-])(curl|wget)[[:space:]]+[^;&|]*(--request[=[:space:]]+(DELETE|PUT|PATCH)|-X[[:space:]]*(DELETE|PUT|PATCH))($|[^[:alnum:]_.-])'

    # curl/wget reading credential files into POST/PUT bodies — defense-in-
    # depth on top of block-protected-files.sh in case a path slips by.
    '(^|[^[:alnum:]_.-])(curl|wget)[[:space:]]+[^;&|]*(--data-binary|--data|-d)[[:space:]]*@[^;&|[:space:]]*(\.aws|\.kube|\.ssh|\.azure|\.config/gcloud|\.terraform|\.codex/auth)'

    # AWS S3 cp/sync/mv that pulls credentials or local config dirs out of the
    # workspace. block-protected-files.sh covers cat/grep on these paths;
    # this catches the case where the agent uploads them via the AWS CLI.
    '(^|[^[:alnum:]_.-])aws[[:space:]]+s3[[:space:]]+(cp|sync|mv)[[:space:]]+[^;&|]*(\.aws|\.kube|\.ssh|\.azure|\.config/gcloud|\.codex/auth|/etc/shadow)'

    # Grafana and Prometheus destructive API/admin operations
    '(^|[^[:alnum:]_.-])curl[^;&|]*(-X[[:space:]]*DELETE|--request[=[:space:]]*DELETE)[^;&|]*(/api/dashboards|/api/datasources|/api/admin)'
    '(^|[^[:alnum:]_.-])curl[^;&|]*(/api/v1/admin/tsdb/delete_series|/api/v1/admin/tsdb/clean_tombstones)'
    '(^|[^[:alnum:]_.-])promtool[[:space:]]+tsdb[[:space:]]+(delete|clean|bench-write)($|[^[:alnum:]_.-])'

    # Host firewall and network sabotage
    '(^|[^[:alnum:]_.-])iptables[[:space:]]+(-F|--flush)($|[^[:alnum:]_.-])'
    '(^|[^[:alnum:]_.-])nft[[:space:]]+flush($|[^[:alnum:]_.-])'
    '(^|[^[:alnum:]_.-])ufw([^;&|]*[[:space:]])disable($|[^[:alnum:]_.-])'
    '(^|[^[:alnum:]_.-])firewall-cmd([^;&|]*[[:space:]])--panic-on($|[^[:alnum:]_.-])'
    '(^|[^[:alnum:]_.-])nmcli[[:space:]]+networking[[:space:]]+off($|[^[:alnum:]_.-])'
    '(^|[^[:alnum:]_.-])ip[[:space:]]+route[[:space:]]+(flush|del|delete|replace[[:space:]]+default)($|[^[:alnum:]_.-])'
    '(^|[^[:alnum:]_.-])ip[[:space:]]+addr[[:space:]]+flush($|[^[:alnum:]_.-])'
    '(^|[^[:alnum:]_.-])ip[[:space:]]+link[[:space:]]+set[^;&|]*[[:space:]]+down($|[^[:alnum:]_.-])'
    '(^|[^[:alnum:]_.-])(echo|printf|cat|sed)[^;&|]*(>|>>|-i)[^;&|]*(/etc/hosts|/etc/resolv\.conf)'
    '(^|[^[:alnum:]_.-])resolvectl[[:space:]]+dns[^;&|]*0\.0\.0\.0'
    '(^|[^[:alnum:]_.-])iptables[^;&|]*(-P[[:space:]]+(INPUT|OUTPUT|FORWARD)[[:space:]]+DROP|--policy[[:space:]]+(INPUT|OUTPUT|FORWARD)[[:space:]]+DROP|-X|--delete-chain|-t[[:space:]]+nat[[:space:]]+(-F|--flush))'
    '(^|[^[:alnum:]_.-])nft[[:space:]]+(delete|destroy|reset)[^;&|]*(table|chain|ruleset)'

    # Stop/disable/mask core host services
    '(^|[^[:alnum:]_.-])systemctl[^;&|]*(stop|disable|mask)[^;&|]*(NetworkManager|ssh|sshd|docker|containerd)($|[^[:alnum:]_.-])'

    # Cron / at / user-level systemd persistence. ~/.config/systemd is in the
    # protected-files hook, but crontab(1) writes via a setuid daemon so the
    # bwrap filesystem boundary does not cover it. systemctl --user enable
    # creates a user-mode persistent unit that survives the Codex session.
    '(^|[^[:alnum:]_.-])crontab($|[[:space:]])'
    '(^|[^[:alnum:]_.-])at[[:space:]]+(-?[fmlqrcvtMqcdb]|now|noon|midnight|teatime|tomorrow|next)'
    '(^|[^[:alnum:]_.-])batch[[:space:]]+(-?[fmlq]|<)'
    '(^|[^[:alnum:]_.-])systemctl[[:space:]]+--user[[:space:]]+(enable|start|link|daemon-reload|reload|restart)($|[^[:alnum:]_.-])'

    # Shell persistence, encoded payload execution, and eval downloader patterns
    '(^|[^[:alnum:]_.-])(echo|printf|cat)[^;&|]*(>|>>)[^;&|]*(\.bashrc|\.zshrc|\.profile|authorized_keys)'
    '(^|[^[:alnum:]_.-])tee[[:space:]]+(-a[[:space:]]+)?[^;&|]*(\.bashrc|\.zshrc|\.profile|authorized_keys)'
    '(^|[^[:alnum:]_.-])base64[[:space:]]+-d[^;&|]*(\|[[:space:]]*(bash|sh)|>[[:space:]]*/tmp/)'
    '(^|[^[:alnum:]_.-])openssl[[:space:]]+enc[[:space:]]+-d[^;&|]*(\|[[:space:]]*(bash|sh)|>[[:space:]]*/tmp/)'
    '(^|[^[:alnum:]_.-])eval[^;&|]*\$\([^)]*(curl|wget|base64|openssl)'
)

init_hook_input || exit 0

if command_matches_patterns "${BLOCKED_COMMAND_PATTERNS[@]}"; then
    reason="Blocked by Codex hook: dangerous Bash command matched policy pattern.
Command: $(command_for_reason)"
    append_blocked_log "$reason" "embedded-blocked-command-patterns" "$MATCHED_PATTERN"
    deny_pre_tool_use "$reason"
fi
