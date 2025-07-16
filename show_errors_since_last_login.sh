#!/usr/bin/env bash

LOG_FILE=~/projects/uptime_monitor/network_monitor.log
LAST_LOGIN_FILE=~/.last_login_time
LAST_LOGIN=$(cat "$LAST_LOGIN_FILE" 2>/dev/null || echo 0)

# grep pulls lines around "ERROR", then awk filters by date
grep -B2 -A4 "❌" "$LOG_FILE" | awk -v last_login="$LAST_LOGIN" '
{
  datetime = $1 " " $2
  cmd = "date -d \"" datetime "\" +%s"
  cmd | getline epoch
  close(cmd)
  if (epoch > last_login) {
    print
  }
}'
