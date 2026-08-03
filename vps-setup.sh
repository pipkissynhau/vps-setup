#!/usr/bin/env bash

set -euo pipefail

# =================================   CONFIG    ================================= 

NEW_USER=""
NEW_USER_PASSWORD=""

SSH_PORT=""
SSH_PUBKEY=""

PACKAGES=(
    ufw
)

# =================================   CONFIG    ================================= 

#   root check
if [[ $EUID -ne 0 ]]; then
    echo "ERROR: run as root"
    exit 1
fi

log() {
    echo "[$(date '+%d-%m-%Y %H:%M:%S')] $1"
}

log "Updating system..."
apt update -y && apt upgrade -y

log "Installing packages: ${PACKAGES[*]}"
apt install -y "${PACKAGES[@]}"

log "Adding new user $NEW_USER"
adduser --disabled-password --gecos "" "$NEW_USER"
usermod -aG sudo "$NEW_USER"
echo "$NEW_USER:$NEW_USER_PASSWORD" | chpasswd

log "Setting up SSH..."

USER_HOME=$(grep "^${NEW_USER}:" /etc/passwd | awk -F: '{print $6}')
SSH_DIR="$USER_HOME/.ssh"

mkdir -p "$SSH_DIR"
touch "$SSH_DIR/authorized_keys"

echo "$SSH_PUBKEY" >> "$SSH_DIR/authorized_keys"

chmod 700 "$SSH_DIR" && chmod 600 "$SSH_DIR/authorized_keys"
chown -R "$NEW_USER":"$NEW_USER" "$SSH_DIR"

SSHD_CONFIG="/etc/ssh/sshd_config.d/00-sshd.conf"
touch "$SSHD_CONFIG"

cat > "$SSHD_CONFIG" <<EOF
Port $SSH_PORT
PermitRootLogin no
PubkeyAuthentication yes
PasswordAuthentication no

KbdInteractiveAuthentication no
UsePAM yes
EOF

log "Checking SSH config..."

if sshd -t; then
  echo "All good"
else
  echo "ERROR: something is wrong with SSH config" >&2
  rm -f "$SSHD_CONFIG"
  exit 1
fi

#   ufw

if echo "${PACKAGES[@]}" | grep -qw "ufw"; then
    log "Setting up UFW..."

    ufw default deny incoming
    ufw default allow outgoing
    ufw allow "$SSH_PORT"/tcp comment 'SSH'

    ufw --force enable
    ufw status verbose
fi

##  if echo "${PACKAGES[@]}" | grep -qw "PACKAGE NAME HERE"; then
##  fi

log "Restarting SSH..."
systemctl restart ssh

IP_ADDR=$(hostname -I | awk '{print $1}')

cat <<EOF
============================================================
 New User            : $NEW_USER
 SSH port            : $SSH_PORT
 SSH root login      : disabled
 Password login      : disabled (key only)
 Firewall (UFW)      : enabled, ports allowed: $SSH_PORT
 
 Try connecting with:
   ssh -p $SSH_PORT $NEW_USER@$IP_ADDR
============================================================
EOF