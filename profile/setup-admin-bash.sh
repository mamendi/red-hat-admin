#!/bin/bash
# Red Hat Admin Bash Pack Installer
# Works on RHEL, Rocky, Alma, CentOS

BASHRC="$HOME/.bashrc"
BACKUP="$HOME/.bashrc.backup.$(date +%F-%H%M%S)"

echo "[*] Backing up current .bashrc to $BACKUP"
cp "$BASHRC" "$BACKUP"

echo "[*] Adding Admin Bash Pack..."

cat << 'EOF' >> "$BASHRC"

#############################
# Red Hat Admin Bash Pack
#############################

### ====== COLORIZED & SAFE FILE COMMANDS ======
alias ls='ls --color=always'
alias ll='ls -lh --color=always'
alias la='ls -lha --color=always'
alias l.='ls -d .* --color=always'
alias cp='cp -i'
alias mv='mv -i'
alias rm='rm -i'

### ====== DISK & MEMORY SHORTCUTS ======
alias df='df -hT'
alias du='du -h --max-depth=1'
alias meminfo='free -h'
alias cpuinfo='lscpu'
alias topcpu='ps -eo pid,ppid,cmd,%mem,%cpu --sort=-%cpu | head'

### ====== NAVIGATION ======
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'

### ====== NETWORKING ======
alias myip='hostname -I | awk "{print \$1}"'
alias ports='ss -tuln'
alias listen='ss -lntp'

### ====== GREP ======
alias grep='grep --color=auto'
alias egrep='egrep --color=auto'
alias fgrep='fgrep --color=auto'

### ====== PACKAGE MANAGEMENT ======
alias update='sudo dnf upgrade --refresh -y'
alias install='sudo dnf install'
alias remove='sudo dnf remove'
alias searchpkg='dnf search'

### ====== SERVICE MANAGEMENT ======
alias start='sudo systemctl start'
alias stop='sudo systemctl stop'
alias restart='sudo systemctl restart'
alias status='systemctl status'

### ====== LOG VIEWERS ======
logtail() { sudo tail -f /var/log/"$1"; }
loggrep() { sudo grep -i "$1" /var/log/"$2"; }

### ====== MONITORING HELPERS ======
sysmon() {
    echo "===== CPU & Memory ====="
    top -b -n1 | head -15
    echo
    echo "===== Disk Usage ====="
    df -hT
    echo
    echo "===== Network Connections ====="
    ss -tuln
}

### ====== QUICK TROUBLESHOOT ======
findbig() { sudo du -ah / | sort -rh | head -n 20; }
servicelog() { sudo journalctl -u "$1" -n 50 --no-pager; }

### ====== CUSTOM COLOR PROMPT ======
RED="\[\033[0;31m\]"
GREEN="\[\033[0;32m\]"
YELLOW="\[\033[0;33m\]"
BLUE="\[\033[0;34m\]"
RESET="\[\033[0m\]"

parse_git_branch() {
    git branch 2>/dev/null | sed -n '/\* /s///p'
}

if [[ $EUID -ne 0 ]]; then
    PS1="${GREEN}\u@\h${YELLOW} \w${BLUE} \$(parse_git_branch)${RESET}\$ "
else
    PS1="${RED}\u@\h${YELLOW} \w${BLUE} \$(parse_git_branch)${RESET}# "
fi

EOF

echo "[*] Reloading Bash..."
source "$BASHRC"

echo "[+] Admin Bash Pack installed successfully!"
