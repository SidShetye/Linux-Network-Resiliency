#!/bin/bash

# Enhanced Network monitoring script for Raspberry Pi
# Created: $(date)
# Advanced recovery mechanisms for stubborn network failures

# Log file location
LOG_FILE="/home/sid/projects/uptime_monitor/network_monitor.log"
MAX_LOG_SIZE=5242880  # 5MB
MAX_LOG_FILES=5       # Maximum number of old log files to keep

# Configuration
MAX_CONSECUTIVE_FAILURES=3    # Number of failures before aggressive reset
FAILURE_COUNT_FILE="/tmp/network_failures"
DHCP_TIMEOUT=30               # DHCP timeout in seconds
REBOOT_THRESHOLD=3            # Number of complete failures before reboot

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

# Function to track consecutive failures
track_failure() {
  local current_count=0
  if [ -f "$FAILURE_COUNT_FILE" ]; then
    current_count=$(cat "$FAILURE_COUNT_FILE")
  fi
  current_count=$((current_count + 1))
  echo "$current_count" > "$FAILURE_COUNT_FILE"
  log_message "⚠️ Consecutive failure count: $current_count"
}

# Function to reset failure count
reset_failure_count() {
  rm -f "$FAILURE_COUNT_FILE"
  log_message "✅ Failure count reset - network recovered"
}

# Function to check if we should reboot
should_reboot() {
  if [ -f "$FAILURE_COUNT_FILE" ]; then
    local count=$(cat "$FAILURE_COUNT_FILE")
    if [ "$count" -ge "$REBOOT_THRESHOLD" ]; then
      return 0
    fi
  fi
  return 1
}

# Function to check internet connectivity
check_internet() {
  # Ping multiple DNS servers for redundancy
  local dns_servers=("8.8.8.8" "1.1.1.1" "208.67.222.222")
  local success_count=0
  
  for dns in "${dns_servers[@]}"; do
    if ping -c 1 -W 3 "$dns" > /dev/null 2>&1; then
      success_count=$((success_count + 1))
    fi
  done
  
  # Require at least 2 successful pings
  if [ $success_count -ge 2 ]; then
    return 0
  else
    return 1
  fi
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

# Function to get detailed interface status
get_interface_status() {
  log_message "📊 Interface status:"
  log_message "$(ip addr show wlan0 2>&1)"
  log_message "$(iwconfig wlan0 2>&1)"
  log_message "$(cat /proc/net/wireless 2>&1)"
}

# Function to reset USB bus (for USB WiFi adapters)
reset_usb_bus() {
  log_message "🔄 Attempting USB bus reset"
  
  # Find the USB device for wlan0
  local usb_path=$(readlink -f /sys/class/net/wlan0/device/../../../ 2>/dev/null)
  if [ -d "$usb_path" ]; then
    local bus=$(basename "$usb_path")
    log_message "Found USB device on bus: $bus"
    
    # Unbind and rebind the USB device
    if [ -f "/sys/bus/usb/drivers/usb/unbind" ]; then
      echo "$bus" | sudo tee /sys/bus/usb/drivers/usb/unbind > /dev/null 2>&1
      sleep 2
      echo "$bus" | sudo tee /sys/bus/usb/drivers/usb/bind > /dev/null 2>&1
      sleep 5
      log_message "USB bus reset completed"
      return 0
    fi
  fi
  
  log_message "❌ USB bus reset failed"
  return 1
}

# Function to reload WiFi kernel modules
reload_wifi_modules() {
  log_message "🔄 Reloading WiFi kernel modules"
  
  # Unload modules
  sudo modprobe -r brcmfmac brcmutil cfg80211 2>/dev/null
  sleep 2
  
  # Reload modules
  sudo modprobe brcmfmac
  sudo modprobe brcmutil
  sudo modprobe cfg80211
  sleep 5
  
  log_message "WiFi kernel modules reloaded"
}

# Function to force DHCP renewal
force_dhcp_renewal() {
  log_message "🔄 Forcing DHCP renewal"
  
  # Release current DHCP lease
  sudo dhclient -r wlan0 2>/dev/null
  
  # Request new DHCP lease with timeout
  sudo timeout $DHCP_TIMEOUT dhclient wlan0
  
  # Check if we got an IP
  if check_wlan0; then
    log_message "✅ DHCP renewal successful"
    return 0
  else
    log_message "❌ DHCP renewal failed"
    return 1
  fi
}

# Function to restart wlan0 interface with enhanced recovery
restart_wlan0_enhanced() {
  log_message "🔄 Enhanced wlan0 restart sequence"
  
  # Get current status for debugging
  get_interface_status
  
  # Try standard restart first
  log_message "Step 1: Standard interface restart"
  sudo ip link set wlan0 down
  sleep 2
  sudo ip link set wlan0 up
  sleep 5
  
  if check_wlan0; then
    log_message "✅ Standard restart successful"
    return 0
  fi
  
  # Try DHCP renewal
  log_message "Step 2: DHCP renewal"
  if force_dhcp_renewal; then
    return 0
  fi
  
  # Try USB bus reset (if applicable)
  log_message "Step 3: USB bus reset"
  if reset_usb_bus; then
    sleep 10
    if check_wlan0; then
      return 0
    fi
  fi
  
  # Try reloading kernel modules
  log_message "Step 4: Reload kernel modules"
  reload_wifi_modules
  
  # Wait for interface to reappear
  local retry_count=0
  while [ $retry_count -lt 10 ]; do
    if ip link show wlan0 > /dev/null 2>&1; then
      break
    fi
    sleep 2
    retry_count=$((retry_count + 1))
  done
  
  # Bring interface up
  sudo ip link set wlan0 up
  sleep 10
  
  if check_wlan0; then
    log_message "✅ Kernel module reload successful"
    return 0
  fi
  
  log_message "❌ All enhanced restart attempts failed"
  return 1
}

# Function to restart wpa_supplicant with enhanced recovery
restart_wpa_supplicant_enhanced() {
  log_message "🔄 Enhanced wpa_supplicant restart"
  
  # Stop wpa_supplicant
  sudo systemctl stop wpa_supplicant
  sleep 2
  
  # Kill any remaining processes
  sudo pkill -f wpa_supplicant
  
  # Clear any stale socket files
  sudo rm -f /var/run/wpa_supplicant/wlan0
  
  # Start wpa_supplicant
  sudo systemctl start wpa_supplicant
  
  # Wait for connection
  sleep 15
  
  # Force DHCP renewal
  force_dhcp_renewal
  
  if check_wlan0 && check_internet; then
    log_message "✅ Enhanced wpa_supplicant restart successful"
    return 0
  else
    log_message "❌ Enhanced wpa_supplicant restart failed"
    return 1
  fi
}

# Function to restart networking service with enhanced recovery
restart_networking_enhanced() {
  log_message "🔄 Enhanced networking service restart"
  
  # Stop networking service
  sudo systemctl stop networking
  sleep 2
  
  # Flush all network configurations
  sudo ip addr flush dev wlan0
  sudo ip route flush dev wlan0
  
  # Start networking service
  sudo systemctl start networking
  
  # Wait for initialization
  sleep 15
  
  # Force DHCP renewal
  force_dhcp_renewal
  
  if check_wlan0 && check_internet; then
    log_message "✅ Enhanced networking service restart successful"
    return 0
  else
    log_message "❌ Enhanced networking service restart failed"
    return 1
  fi
}

# Function to restart wlan0 interface (original method for compatibility)
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

# Function to restart wpa_supplicant (original method for compatibility)
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

# Function to restart networking service (original method for compatibility)
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

# Function to perform system reboot as last resort
perform_reboot() {
  log_message "🚨 CRITICAL: All recovery attempts failed"
  log_message "🔄 Initiating system reboot in 30 seconds..."
  
  # Create reboot marker
  echo "$(timestamp)" > /tmp/network_reboot_marker
  
  # Sync filesystems
  sync
  
  # Schedule reboot
  sudo shutdown -r +1 "Network recovery reboot due to persistent failures"
  
  # Exit script
  exit 1
}

# Function to perform aggressive recovery
perform_aggressive_recovery() {
  log_message "🔥 Performing aggressive recovery sequence"
  
  # Try enhanced wlan0 restart
  if restart_wlan0_enhanced; then
    return 0
  fi
  
  # Try enhanced wpa_supplicant restart
  if restart_wpa_supplicant_enhanced; then
    return 0
  fi
  
  # Try enhanced networking restart
  if restart_networking_enhanced; then
    return 0
  fi
  
  log_message "❌ All aggressive recovery attempts failed"
  return 1
}

# Main script execution

log_message "=============================================="
log_message "Enhanced Network Monitor Starting"

# Check if we're recovering from a reboot
if [ -f /tmp/network_reboot_marker ]; then
  log_message "📋 System recovered from network reboot"
  rm -f /tmp/network_reboot_marker
fi

# Check wlan0 status
if check_wlan0; then
  WLAN0_IP=$(ip -4 addr show wlan0 | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
  log_message "✅ wlan0 interface is UP with IP: $WLAN0_IP"
  
  # Check internet connectivity
  if check_internet; then
    log_message "✅ Internet connectivity confirmed"
    reset_failure_count
  else
    log_message "❌ Internet connectivity failed"
    
    # Try to fix connectivity issues
    log_message "⚠️ Attempting connectivity recovery"
    
    if restart_wlan0_enhanced; then
      if check_internet; then
        log_message "⚠️ Fixed connectivity by enhanced wlan0 restart"
        reset_failure_count
      fi
    elif restart_wpa_supplicant_enhanced; then
      log_message "⚠️ Fixed connectivity by enhanced wpa_supplicant restart"
      reset_failure_count
    elif restart_networking_enhanced; then
      log_message "⚠️ Fixed connectivity by enhanced networking restart"
      reset_failure_count
    else
      log_message "☠️ All connectivity recovery attempts failed"
      track_failure
      
      if should_reboot; then
        perform_reboot
      fi
    fi
  fi
else
  log_message "❌ wlan0 interface is DOWN or has no IP"
  
  # Check if we should use aggressive recovery
  if [ -f "$FAILURE_COUNT_FILE" ] && [ $(cat "$FAILURE_COUNT_FILE") -ge $MAX_CONSECUTIVE_FAILURES ]; then
    log_message "🔄 Using aggressive recovery due to repeated failures"
    
    if perform_aggressive_recovery; then
      log_message "⚠️ Successfully recovered with aggressive measures"
      reset_failure_count
    else
      log_message "☠️ Aggressive recovery failed"
      track_failure
      
      if should_reboot; then
        perform_reboot
      fi
    fi
  else
    # Try standard recovery first
    log_message "🔄 Attempting standard recovery"
    
    if restart_wlan0; then
      log_message "⚠️ Successfully brought wlan0 back online"
      reset_failure_count
    else
      # Try more aggressive measures
      if restart_wpa_supplicant; then
        log_message "⚠️ Successfully brought wlan0 back online via wpa_supplicant restart"
        reset_failure_count
      elif restart_networking; then
        log_message "⚠️ Successfully brought wlan0 back online via networking service restart"
        reset_failure_count
      else
        log_message "☠️ All standard recovery attempts failed"
        track_failure
        
        if should_reboot; then
          perform_reboot
        fi
      fi
    fi
  fi
fi

log_message "Enhanced network monitoring check completed"
log_message "----------------------------------------------"

exit 0