#!/bin/bash
set -euo pipefail

SWITCH_IP="192.168.1.10"
USER="user"

ACTION="${1:-}"
shift || true

if [[ -z "${ACTION}" ]]; then
  echo "Usage: $0 {on|off|status|restart} [id PORTS]"
  echo "Examples:"
  echo "  $0 status id 21"
  echo "  $0 off    id 21,22,23"
  echo "  $0 on     id 5-7"
  exit 2
fi

ts() { date '+%Y-%m-%d %H:%M:%S'; }

ssh_run() {
  ssh -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new \
    "${USER}@${SWITCH_IP}" "$1"
}

# Accept: single number (21), range (5-7), list (1,4,9-12), or mixed
is_valid_ports() {
  local s="$1"
  [[ "$s" =~ ^[0-9]+([,-][0-9]+)*(-[0-9]+)?(,[0-9]+([,-][0-9]+)*(-[0-9]+)?)*$ ]] && return 0
  # simpler robust check: only digits, comma, dash allowed, and not empty
  [[ -n "$s" && "$s" =~ ^[0-9,-]+$ ]]
}

MODE=""
case "$ACTION" in
  off)    MODE="off" ;;
  on)     MODE="auto" ;;
  status) MODE="" ;;
  restart) MODE="" ;;
  *)
    echo "Usage: $0 {on|off|status|restart} [id PORTS]"
    exit 2
    ;;
esac

# Parse optional "id PORTS"
PORTS=""
if [[ "${1:-}" == "id" ]]; then
  shift
  PORTS="${1:-}"
  if [[ -z "$PORTS" ]]; then
    echo "Error: missing PORTS after 'id'"
    exit 2
  fi
  shift || true
fi

# Validate ports string if provided
if [[ -n "$PORTS" ]] && ! is_valid_ports "$PORTS"; then
  echo "Error: invalid port format: '$PORTS'"
  echo "Allowed examples: 21 | 5-7 | 1,4,9-12"
  exit 2
fi

# Build swctrl command
case "$ACTION" in
  status)
    CMD="swctrl poe show"
    [[ -n "$PORTS" ]] && CMD+=" id ${PORTS}"
    ;;
  restart)
    CMD="swctrl poe restart"
    [[ -n "$PORTS" ]] && CMD+=" id ${PORTS}"
    ;;
  on|off)
    CMD="swctrl poe set ${MODE}"
    [[ -n "$PORTS" ]] && CMD+=" id ${PORTS}"
    ;;
esac

LOG="/var/log/poe-${ACTION}.log"

{
  echo "[$(ts)] ACTION=${ACTION} SWITCH=${SWITCH_IP} CMD=${CMD}"
  echo "-----"
  # retry only for changing state
  if [[ "$ACTION" == "on" || "$ACTION" == "off" || "$ACTION" == "restart" ]]; then
    for i in 1 2 3; do
      if ssh_run "$CMD"; then
        echo "[$(ts)] OK"
        exit 0
      fi
      echo "[$(ts)] WARN: attempt $i failed, retrying..."
      sleep 2
    done
    echo "[$(ts)] ERROR: failed after retries"
    exit 1
  else
    # status: just show output
    ssh_run "$CMD"
    echo "-----"
  fi
} | tee -a "$LOG"
