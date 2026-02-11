#!/bin/bash 

set -euo pipefail 

SWITCH_IP="192.168.1.10" 
PORT_ID="21" 
ACTION="${1:-}" 
USER="user" 
LOG="/var/log/poe-port${PORT_ID}.log" 

ts() { date '+%Y-%m-%d %H:%M:%S'; } 
run() { 
  ssh -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new \ 
    "${USER}@${SWITCH_IP}" "$1" 
} 

case "$ACTION" in 
  off) 
    CMD="swctrl poe set off id ${PORT_ID}" 
    ;; 
  on) 
    CMD="swctrl poe set auto id ${PORT_ID}" 
    ;; 
  *) 
    echo "Usage: $0 {on|off}" >&2 
    exit 2 
    ;; 
esac 

{ 
  echo "[$(ts)] ACTION=${ACTION} SWITCH=${SWITCH_IP} PORT=${PORT_ID}" 
  # retry 3 times 
  for i in 1 2 3; do 
    if run "$CMD"; then 
      echo "[$(ts)] OK: $CMD" 
      exit 0 
    fi 
    echo "[$(ts)] WARN: attempt $i failed, retrying..." 
    sleep 2 
  done 
  echo "[$(ts)] ERROR: failed after retries: $CMD" 
  exit 1 
} >> "$LOG" 2>&1 
