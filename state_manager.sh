#!/bin/bash

# Centralized state management for uptime monitor scripts
# This provides a consistent interface for managing state across all scripts

# State directory - centralized location for all state files
STATE_DIR="/home/sid/projects/uptime_monitor/state"
LOG_DIR="/home/sid/projects/uptime_monitor/logs"

# Ensure directories exist
mkdir -p "$STATE_DIR" "$LOG_DIR"

# State files
FAILURE_COUNT_FILE="$STATE_DIR/network_failures"
LAST_LOGIN_FILE="$STATE_DIR/last_login_time"
REBOOT_MARKER_FILE="$STATE_DIR/network_reboot_marker"

# Log files
NETWORK_LOG_FILE="$LOG_DIR/network_monitor.log"

# Configuration
MAX_LOG_SIZE=5242880  # 5MB
MAX_LOG_FILES=5       # Maximum number of old log files to keep
MAX_CONSECUTIVE_FAILURES=3    # Number of failures before aggressive reset
DHCP_TIMEOUT=30               # DHCP timeout in seconds
REBOOT_THRESHOLD=3            # Number of complete failures before reboot

# Function to get timestamp
get_timestamp() {
    date "+%Y-%m-%d %H:%M:%S"
}

# Function to get filename-safe timestamp
get_filename_timestamp() {
    date "+%Y%m%d-%H%M%S"
}

# Function to track consecutive failures
track_failure() {
    local current_count=0
    if [ -f "$FAILURE_COUNT_FILE" ]; then
        current_count=$(cat "$FAILURE_COUNT_FILE")
    fi
    current_count=$((current_count + 1))
    echo "$current_count" > "$FAILURE_COUNT_FILE"
    echo "$current_count"
}

# Function to reset failure count
reset_failure_count() {
    rm -f "$FAILURE_COUNT_FILE"
}

# Function to get current failure count
get_failure_count() {
    if [ -f "$FAILURE_COUNT_FILE" ]; then
        cat "$FAILURE_COUNT_FILE"
    else
        echo "0"
    fi
}

# Function to check if we should reboot
should_reboot() {
    local count=$(get_failure_count)
    [ "$count" -ge "$REBOOT_THRESHOLD" ]
}

# Function to set last login time
set_last_login_time() {
    local timestamp=${1:-$(date +%s)}
    echo "$timestamp" > "$LAST_LOGIN_FILE"
}

# Function to get last login time
get_last_login_time() {
    if [ -f "$LAST_LOGIN_FILE" ]; then
        cat "$LAST_LOGIN_FILE"
    else
        echo "0"
    fi
}

# Function to set reboot marker
set_reboot_marker() {
    get_timestamp > "$REBOOT_MARKER_FILE"
}

# Function to check and clear reboot marker
check_reboot_marker() {
    if [ -f "$REBOOT_MARKER_FILE" ]; then
        rm -f "$REBOOT_MARKER_FILE"
        return 0
    fi
    return 1
}

# Function to clean old log files
clean_old_logs() {
    local log_count=$(ls -t "${NETWORK_LOG_FILE}".*.gz 2>/dev/null | wc -l)
    if [ "$log_count" -gt "$MAX_LOG_FILES" ]; then
        ls -t "${NETWORK_LOG_FILE}".*.gz | tail -n +$((MAX_LOG_FILES + 1)) | xargs rm -f
    fi
}

# Function to rotate log if needed
rotate_log_if_needed() {
    if [ -f "$NETWORK_LOG_FILE" ] && [ $(stat -c%s "$NETWORK_LOG_FILE") -gt $MAX_LOG_SIZE ]; then
        local ts=$(get_filename_timestamp)
        mv "$NETWORK_LOG_FILE" "${NETWORK_LOG_FILE}.${ts}"
        gzip "${NETWORK_LOG_FILE}.${ts}"
        clean_old_logs
        return 0
    fi
    return 1
}

# Function to log messages with proper error formatting
log_message() {
    local level="$1"
    local message="$2"
    local timestamp=$(get_timestamp)
    
    # Format: TIMESTAMP [LEVEL] MESSAGE
    echo "$timestamp [$level] $message" >> "$NETWORK_LOG_FILE"
    
    # Rotate log if needed
    if rotate_log_if_needed; then
        echo "$timestamp [INFO] Log file rotated and compressed" >> "$NETWORK_LOG_FILE"
    fi
}

# Convenience functions for different log levels
log_info() {
    log_message "INFO" "$1"
}

log_error() {
    log_message "ERROR" "$1"
}

log_warning() {
    log_message "WARNING" "$1"
}

log_success() {
    log_message "SUCCESS" "$1"
}