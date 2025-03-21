#!/bin/bash

# Meant for Debian Linux Severs
# NOTE: This script leaves password authentication enabled for SSH
# Instructions for setting up key-based auth are at the end

set -e

apt update
apt upgrade -y
apt autoremove -y

if ! systemctl is-active systemd-timesyncd >/dev/null; then
    systemctl enable systemd-timesyncd
    systemctl start systemd-timesyncd
fi

if [ -n "$SUDO_USER" ]; then
    USER_HOME="/home/$SUDO_USER"
    if [ ! -d "$USER_HOME/.ssh" ]; then
        mkdir -p "$USER_HOME/.ssh"
        chown "$SUDO_USER":"$SUDO_USER" "$USER_HOME/.ssh"
        chmod 700 "$USER_HOME/.ssh"
    fi
    touch "$USER_HOME/.ssh/authorized_keys"
    chown "$SUDO_USER":"$SUDO_USER" "$USER_HOME/.ssh/authorized_keys"
    chmod 600 "$USER_HOME/.ssh/authorized_keys"

    echo 'PATH="$PATH:/sbin"' >> "/home/$SUDO_USER/.bashrc"
    echo "alias ls='ls -lhA --color=auto'" >> "/home/$SUDO_USER/.bashrc"
    chown "$SUDO_USER":"$SUDO_USER" "/home/$SUDO_USER/.bashrc"
else
    echo "Warning: SUDO_USER not set. Skipping .bashrc modifications."
fi

sed -i 's/#PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
sed -i 's/#LogLevel INFO/LogLevel VERBOSE/' /etc/ssh/sshd_config
echo "MaxAuthTries 3" >> /etc/ssh/sshd_config
systemctl restart ssh

apt install -y fail2ban
cat <<EOF > /etc/fail2ban/jail.local
[sshd]
enabled = true
maxretry = 3
findtime = 5m
bantime = 30m
EOF
systemctl enable fail2ban
systemctl restart fail2ban

# TODO: Will need to add rules for http. 80/tcp for http and 443/tcp for https
# Do we even need to allow http or no?
apt install -y ufw
ufw default deny incoming # Should be default, but let's be sure
ufw default allow outgoing # Also should be default
ufw allow 22/tcp
ufw limit 22/tcp
ufw logging on
ufw --force enable

chmod 600 /etc/shadow

apt install -y vim

apt install -y auditd
if ! systemctl is-enabled auditd >/dev/null; then
    systemctl enable auditd
fi
if ! systemctl is-active auditd >/dev/null; then
    systemctl start auditd
fi
/sbin/auditctl -e 1
/sbin/auditctl -a always,exit -F path=/etc/ssh/sshd_config

echo "blacklist floppy" |  tee -a /etc/modprobe.d/blacklist.conf > /dev/null
echo "blacklist firewire-core" |  tee -a /etc/modprobe.d/blacklist.conf > /dev/null
echo "blacklist bluetooth" |  tee -a /etc/modprobe.d/blacklist.conf > /dev/null
echo "blacklist soundcore" |  tee -a /etc/modprobe.d/blacklist.conf > /dev/null
update-initramfs -u

cat <<'EOF' > /usr/local/bin/upgrade-server.sh
#!/bin/bash
LOGFILE="/var/log/server-upgrades.log"
echo "Upgrade started at $(date)" >> "$LOGFILE"
apt update >> "$LOGFILE" 2>&1
apt upgrade -y >> "$LOGFILE" 2>&1
apt autoremove -y >> "$LOGFILE" 2>&1
echo "Upgrade completed at $(date)" >> "$LOGFILE"
echo "Check if reboot is needed: /var/run/reboot-required" >> "$LOGFILE"
EOF
chmod +x /usr/local/bin/upgrade-server.sh
echo "0 4 * * * /usr/local/bin/upgrade-server.sh" | crontab -
# if [ -f /var/run/reboot-required ]; then echo "Reboot needed"; else echo "No reboot needed"; fi
# cat /var/run/reboot-required
# tail /var/log/server-upgrades.log

apt install -y apparmor apparmor-profiles
systemctl enable apparmor
systemctl start apparmor

apt install -y postgresql
systemctl enable postgresql
systemctl start postgresql

sed -i 's/#listen_addresses = .*/listen_addresses = localhost/' /etc/postgresql/*/main/postgresql.conf
sed -i 's/#ssl = off/ssl = on/' /etc/postgresql/*/main/postgresql.conf

mkdir -p /etc/postgresql/*/main/certs
openssl req -new -x509 -days 365 -nodes -text -out /etc/postgresql/*/main/certs/server.crt \
    -keyout /etc/postgresql/*/main/certs/server.key -subj "/CN=$(hostname)"
chown postgres:postgres /etc/postgresql/*/main/certs/server.*
chmod 600 /etc/postgresql/*/main/certs/server.*

cat <<EOF > /etc/postgresql/*/main/pg_hba.conf
# Local connections (for SSH tunnel)
local   all   all                trust
hostssl all   all   127.0.0.1/32 md5
# Reject non-SSL connections
hostnossl all all 0.0.0.0/0    reject
EOF
chown postgres:postgres /etc/postgresql/*/main/pg_hba.conf
chmod 600 /etc/postgresql/*/main/pg_hba.conf

systemctl restart postgresql

echo "Server setup complete"

# After running:
# On your machine: ssh-keygen -t ed25519 -f your_ssh_key
# On your machine: scp your_ssh_key.pub user@server.address:/home/user/.ssh
# On the server: cat your_ssh_key.pub >> authorized_keys
# On the VM: sudo vim /etc/ssh/sshd_config
# On your machine: Rename the keys to ed25519 and ed25519.pub
# On your machine: Test ssh with key
# Change #PasswordAuthentication yes to PasswordAuthentication no
# sudo systemctl restart ssh

# Use SSH tunneling for remote DB access: ssh -L 5432:localhost:5432 user@server
# Dadbod connection string: postgresql://user:pass@localhost:5432/dbname?sslmode=require

# TODO: Maybe do 2FA for SSH, but seems a bit extra
# TODO: Possibly use aide or Tripwire to detect file changes. Or Prometheus/SIEM
# TODO: Script backups

# TODO: Grok had an idea for securing shared memory:
# echo "tmpfs /run/shm tmpfs ro,noexec,nosuid 0 0" >> /etc/fstab
# mount -o remount /run/shm
# This is interesting but feels like a footgun. Might revisit down the line

# TODO: Server hardening script here: https://github.com/ovh/debian-cis
