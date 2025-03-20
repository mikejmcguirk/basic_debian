###############################
# Meant for Debian Linux Severs
###############################

apt update
apt upgrade -y
apt autoremove -y

if ! systemctl is-active systemd-timesyncd >/dev/null; then
    systemctl enable systemd-timesyncd
    systemctl start systemd-timesyncd
fi

sed -i 's/#PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
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
# Do we need to allow http or no?
# Grok reasonably suggests having web processes confined to a specifically privileged user
# Suggests AppArmor/SELinux to "prevent escalation"
# "Add profiles" for Nginx/Apache
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
# Maybe do these
# echo 'export PATH="$PATH:/sbin"' >> ~/.bashrc
# source ~/.bashrc
/sbin/auditctl -e 1
/sbin/auditctl -a always,exit -F path=/etc/ssh/sshd_config

echo "blacklist floppy" |  tee -a /etc/modprobe.d/blacklist.conf > /dev/null
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
echo "0 2 * * * /usr/local/bin/upgrade-server.sh" | crontab -

echo "Server setup complete"

# TODO: How do I pull the script in?

# TODO: Maybe do 2FA for SSH, but seems a bit extra
# TODO: Possibly use aide or Tripwire to detect file changes. Or Prometheus/SIEM
# TODO: Script backups

# TODO: Grok had an idea for securing shared memory:
# echo "tmpfs /run/shm tmpfs ro,noexec,nosuid 0 0" >> /etc/fstab
# mount -o remount /run/shm
# This is interesting but feels like a footgun. Might revisit down the line

# TODO: Server hardening script here: https://github.com/ovh/debian-cis
