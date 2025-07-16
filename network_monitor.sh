#!/bin/bash

# Network monitoring script for Raspberry Pi
# Created: $(date)
# Checks system and wlan0 status and takes corrective action when needed

# Log file location
LOG_FILE="/home/sid/projects/uptime_monitor/network_monitor.log"
MAX_LOG_SIZE=5242880  # 5MB
MAX_LOG_FILES=5       # Maximum number of old log files to keep

# Function to get timestamp
timestamp() {
  date "+%Y-%m-%d %H:%M:%S"
}

# Function to get filename-safe timestamp
filename_timestamp() {
  date "+%Y%m%d-%H%M%S"
}

# Function to clean old log files keeping only the most recent ones
clean_old_logs() {
  # List all compressed log files, sort by modification time (oldest first)
  local log_count=$(ls -t "${LOG_FILE}".*.gz 2>/dev/null | wc -l)
  if [ "$log_count" -gt "$MAX_LOG_FILES" ]; then
    # Delete oldest files beyond our limit
    ls -t "${LOG_FILE}".*.gz | tail -n +$((MAX_LOG_FILES + 1)) | xargs rm -f
  fi
}

# Function to log messages
log_message() {
  echo "$(timestamp) - $1" >> "$LOG_FILE"
  
  # Check if log file is too large, rotate if needed
  if [ -f "$LOG_FILE" ] && [ $(stat -c%s "$LOG_FILE") -gt $MAX_LOG_SIZE ]; then
    local ts=$(filename_timestamp)
    mv "$LOG_FILE" "${LOG_FILE}.${ts}"
    gzip "${LOG_FILE}.${ts}"
    echo "$(timestamp) - Log file rotated and compressed" >> "$LOG_FILE"
    clean_old_logs
  fi
}

# Function to check internet connectivity
check_internet() {
  # Ping Google DNS server 3 times with timeout of 2 seconds each
  ping -c 3 -W 2 8.8.8.8 > /dev/null 2>&1
  return $?
}

# Function to check if wlan0 interface exists and is up
check_wlan0() {
  # Check if wlan0 interface exists
  if ! ip link show wlan0 > /dev/null 2>&1; then
    log_message "ERROR: wlan0 interface does not exist"
    return 2
  fi
  
  # Check if wlan0 interface is up
  if ! ip link show wlan0 | grep -q "UP"; then
    log_message "ERROR: wlan0 interface exists but is not UP"
    return 1
  fi
  
  # Check if wlan0 has an IP address
  if ! ip addr show wlan0 | grep -q "inet "; then
    log_message "ERROR: wlan0 interface is UP but has no IP address"
    return 1
  fi
  
  return 0
}

# Function to restart wlan0 interface
restart_wlan0() {
  log_message "Attempting to restart wlan0 interface"
  
  # Try to take down and bring up the interface
  sudo ip link set wlan0 down
  sleep 2
  sudo ip link set wlan0 up
  
  # Wait for interface to initialize
  sleep 5
  
  # Check if the restart fixed the issue
  if check_wlan0; then
    log_message "Successfully restarted wlan0 interface"
    return 0
  else
    log_message "Failed to restart wlan0 interface"
    return 1
  fi
}

# Function to restart network service
restart_networking() {
  log_message "Attempting to restart networking service"
  
  sudo systemctl restart networking
  
  # Wait for networking to initialize
  sleep 10
  
  # Check if the restart fixed the issue
  if check_wlan0 && check_internet; then
    log_message "Successfully restarted networking service"
    return 0
  else
    log_message "Failed to restart networking service"
    return 1
  fi
}

# Function to restart wpa_supplicant
restart_wpa_supplicant() {
  log_message "Attempting to restart wpa_supplicant"
  
  sudo systemctl restart wpa_supplicant
  
  # Wait for wpa_supplicant to initialize
  sleep 5
  
  # Check if the restart fixed the issue
  if check_wlan0 && check_internet; then
    log_message "Successfully restarted wpa_supplicant"
    return 0
  else
    log_message "Failed to restart wpa_supplicant"
    return 1
  fi
}

# Start script

# Check wlan0 status
if check_wlan0; then
  WLAN0_IP=$(ip -4 addr show wlan0 | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
  log_message "✅ wlan0 interface is UP with IP: $WLAN0_IP"
  
  # Check internet connectivity
  if check_internet; then
    log_message "✅ Internet connectivity"
  else
    log_message "❌ Internet connectivity"
    
    # Try to fix connectivity issues
    log_message "⚠️ Trying to fix connectivity issues"
    
    # First try restarting just the interface
    if restart_wlan0; then
      if check_internet; then
        log_message "⚠️ Fixed connectivity by restarting wlan0"
      fi
    # If that fails, try restarting wpa_supplicant
    elif restart_wpa_supplicant; then
      log_message "⚠️ Fixed connectivity by restarting wpa_supplicant"
    # If that fails, try restarting the entire networking service
    elif restart_networking; then
      log_message "⚠️ Fixed connectivity by restarting networking service"
    else
      log_message "☠️ Failed to fix connectivity issues"
    fi
  fi
else
  log_message "❌ wlan0 interface is DOWN"
  
  # Try to fix wlan0 issues
  if restart_wlan0; then
    log_message "⚠️ Successfully brought wlan0 back online"
  else
    # If simple restart doesn't work, try more aggressive measures
    if restart_wpa_supplicant; then
      log_message "⚠️ Successfully brought wlan0 back online via wpa_supplicant restart"
    elif restart_networking; then
      log_message "⚠️ Successfully brought wlan0 back online via networking service restart"
    else
      log_message "☠️ All attempts to bring wlan0 back online failed"
    fi
  fi
fi

# log_message "Network monitoring check completed"
log_message "----------------------------------------------"

exit 0