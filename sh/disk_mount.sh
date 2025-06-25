#!/bin/bash
 
do_disk() {
  echo "=== [DISK] Searching for unmounted usable partition ==="
  FREE_PART=$(lsblk -nr -o NAME,TYPE,MOUNTPOINT,SIZE | awk '$2=="part" && $3=="" && $4+0 > 1 {print $1}' | head -n1)

  if [ -z "$FREE_PART" ]; then
    echo "❌ No usable unmounted partition found"
    exit 1
  fi

  PART="/dev/$FREE_PART"
  echo "✅ Found partition: $PART"

  echo "=== [DISK] Formatting $PART to ext4 ==="
  mkfs.ext4 "$PART"

  echo "=== [DISK] Mounting $PART to $MOUNT_POINT ==="
  mkdir -p "$MOUNT_POINT"
  UUID=$(blkid -s UUID -o value "$PART")
  grep -q "$UUID" /etc/fstab || echo "UUID=$UUID $MOUNT_POINT ext4 defaults 0 2" >> /etc/fstab
  mount -a

  echo "✅ Partition $PART mounted to $MOUNT_POINT"
  df -h | grep "$MOUNT_POINT"
}

do_disk
