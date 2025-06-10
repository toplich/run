#!/bin/bash

CONTAINER_NAME="wg-peer"
DOCKER_BIN="/usr/local/bin/docker"
LOGFILE="/var/log/wg-watchdog.log"

HEALTH=$($DOCKER_BIN inspect --format='{{.State.Health.Status}}' "$CONTAINER_NAME" 2>/dev/null)

if [ "$HEALTH" == "unhealthy" ]; then
  echo "$(date) - Container $CONTAINER_NAME is UNHEALTHY. Restarting..." >> "$LOGFILE"
  $DOCKER_BIN restart "$CONTAINER_NAME"
else
  echo "$(date) - Container $CONTAINER_NAME is $HEALTH." >> "$LOGFILE"
fi
