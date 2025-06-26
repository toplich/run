#!/bin/bash
set -e

# === Variables ===
REPO_USER="veeamrepo"
DISK="/dev/sdb"
MOUNT_POINT="/mnt/veeam"
PUBKEY="ssh-rsa AAAA..."

# === Install required packages ===
apt update && apt install -y xfsprogs openssh-server sudo ufw

# === Create non-root user ===
if ! id "$REPO_USER" &>/dev/null; then
    adduser --disabled-password --gecos "" "$REPO_USER"
fi

# === Add public key for SSH ===
mkdir -p /home/$REPO_USER/.ssh
chmod 700 /home/$REPO_USER/.ssh
echo "$PUBKEY" > /home/$REPO_USER/.ssh/authorized_keys
chmod 600 /home/$REPO_USER/.ssh/authorized_keys
chown -R $REPO_USER:$REPO_USER /home/$REPO_USER/.ssh

# === Format and mount disk ===
mkfs.xfs -b size=4096 -m reflink=1,crc=1 "$DISK"
mkdir -p "$MOUNT_POINT"
UUID=$(blkid -s UUID -o value "$DISK")
grep -q "$MOUNT_POINT" /etc/fstab || echo "UUID=$UUID $MOUNT_POINT xfs defaults 0 0" >> /etc/fstab
mount -a
chown $REPO_USER:$REPO_USER "$MOUNT_POINT"

# === (Optional) Restrict sudo after Veeam setup ===
# deluser "$REPO_USER" sudo
# echo "$REPO_USER ALL=(ALL) !ALL" > /etc/sudoers.d/99-veeamrepo

# === (Optional) Disable SSH password login ===
# sed -i 's/^#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
# systemctl restart ssh

# === (Optional) Lock shell access ===
# usermod -s /usr/sbin/nologin $REPO_USER

echo "✅ System is ready to be added as a Hardened Linux Repository."
