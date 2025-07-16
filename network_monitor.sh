#!/bin/bash

# Network monitoring script for Raspberry Pi
# Created: $(date)
# Monitors network connectivity and performs recovery actions

# Source the centralized state manager
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/state_manager.sh"

# Recovery strategy definitions
declare -A RECOVERY_STRATEGIES=(
    ["basic_interface_restart"]="restart_interface"
    ["dhcp_renewal"]="force_dhcp_renewal"
    ["usb_reset"]="reset_usb_bus"
    ["module_reload"]="reload_wifi_modules"
    ["wpa_supplicant_restart"]="restart_wpa_supplicant"
    ["networking_service_restart"]="restart_networking_service"
)

# Recovery strategy order (from least to most aggressive)
RECOVERY_ORDER=(
    "basic_interface_restart"
    "dhcp_renewal"
    "usb_reset"
    "module_reload"
    "wpa_supplicant_restart"
    "networking_service_restart"
)

# Function to check internet connectivity with early termination
check_internet() {
    local dns_servers=("8.8.8.8" "1.1.1.1" "208.67.222.222")
    
    for dns in "${dns_servers[@]}"; do
        if ping -c 1 -W 3 "$dns" > /dev/null 2>&1; then
            return 0  # Early termination on first success
        fi
    done
    
    return 1
}

# Function to check if wlan0 interface exists and is up
check_wlan0() {
    # Check if wlan0 interface exists
    if ! ip link show wlan0 > /dev/null 2>&1; then
        log_error "wlan0 interface does not exist"
        return 2
    fi
    
    # Check if wlan0 interface is up
    if ! ip link show wlan0 | grep -q "UP"; then
        log_error "wlan0 interface exists but is not UP"
        return 1
    fi
    
    # Check if wlan0 has an IP address
    if ! ip addr show wlan0 | grep -q "inet "; then
        log_error "wlan0 interface is UP but has no IP address"
        return 1
    fi
    
    return 0
}

# Function to get detailed interface status
get_interface_status() {
    log_info "Interface status:"
    log_info "$(ip addr show wlan0 2>&1)"
    log_info "$(iwconfig wlan0 2>&1)"
    log_info "$(cat /proc/net/wireless 2>&1)"
}

# Function to reset USB bus (for USB WiFi adapters)
reset_usb_bus() {
    log_info "Attempting USB bus reset"
    
    local usb_path=$(readlink -f /sys/class/net/wlan0/device/../../../ 2>/dev/null)
    if [ -d "$usb_path" ]; then
        local bus=$(basename "$usb_path")
        log_info "Found USB device on bus: $bus"
        
        if [ -f "/sys/bus/usb/drivers/usb/unbind" ]; then
            echo "$bus" | sudo tee /sys/bus/usb/drivers/usb/unbind > /dev/null 2>&1
            sleep 2
            echo "$bus" | sudo tee /sys/bus/usb/drivers/usb/bind > /dev/null 2>&1
            sleep 5
            log_success "USB bus reset completed"
            return 0
        fi
    fi
    
    log_error "USB bus reset failed"
    return 1
}

# Function to reload WiFi kernel modules
reload_wifi_modules() {
    log_info "Reloading WiFi kernel modules"
    
    # Unload modules
    sudo modprobe -r brcmfmac brcmutil cfg80211 2>/dev/null
    sleep 2
    
    # Reload modules
    sudo modprobe brcmfmac
    sudo modprobe brcmutil
    sudo modprobe cfg80211
    sleep 5
    
    log_success "WiFi kernel modules reloaded"
    
    # Wait for interface to reappear and bring it up
    local retry_count=0
    while [ $retry_count -lt 10 ]; do
        if ip link show wlan0 > /dev/null 2>&1; then
            sudo ip link set wlan0 up
            sleep 5
            return 0
        fi
        sleep 2
        retry_count=$((retry_count + 1))
    done
    
    log_error "Interface did not reappear after module reload"
    return 1
}

# Function to force DHCP renewal
force_dhcp_renewal() {
    log_info "Forcing DHCP renewal"
    
    # Release current DHCP lease
    sudo dhclient -r wlan0 2>/dev/null
    
    # Request new DHCP lease with timeout
    sudo timeout $DHCP_TIMEOUT dhclient wlan0
    
    if check_wlan0; then
        log_success "DHCP renewal successful"
        return 0
    else
        log_error "DHCP renewal failed"
        return 1
    fi
}

# Function to restart wlan0 interface
restart_interface() {
    log_info "Restarting wlan0 interface"
    
    get_interface_status
    
    sudo ip link set wlan0 down
    sleep 2
    sudo ip link set wlan0 up
    sleep 5
    
    if check_wlan0; then
        log_success "Interface restart successful"
        return 0
    else
        log_error "Interface restart failed"
        return 1
    fi
}

# Function to restart wpa_supplicant
restart_wpa_supplicant() {
    log_info "Restarting wpa_supplicant"
    
    # Stop wpa_supplicant
    sudo systemctl stop wpa_supplicant
    sleep 2
    
    # Kill any remaining processes
    sudo pkill -f wpa_supplicant
    
    # Clear any stale socket files
    sudo rm -f /var/run/wpa_supplicant/wlan0
    
    # Start wpa_supplicant
    sudo systemctl start wpa_supplicant
    sleep 15
    
    # Force DHCP renewal
    force_dhcp_renewal
    
    if check_wlan0 && check_internet; then
        log_success "wpa_supplicant restart successful"
        return 0
    else
        log_error "wpa_supplicant restart failed"
        return 1
    fi
}

# Function to restart networking service
restart_networking_service() {
    log_info "Restarting networking service"
    
    # Stop networking service
    sudo systemctl stop networking
    sleep 2
    
    # Flush all network configurations
    sudo ip addr flush dev wlan0
    sudo ip route flush dev wlan0
    
    # Start networking service
    sudo systemctl start networking
    sleep 15
    
    # Force DHCP renewal
    force_dhcp_renewal
    
    if check_wlan0 && check_internet; then
        log_success "Networking service restart successful"
        return 0
    else
        log_error "Networking service restart failed"
        return 1
    fi
}

# Function to perform system reboot as last resort
perform_reboot() {
    log_error "CRITICAL: All recovery attempts failed"
    log_info "Initiating system reboot in 30 seconds..."
    
    # Create reboot marker
    set_reboot_marker
    
    # Sync filesystems
    sync
    
    # Schedule reboot
    sudo shutdown -r +1 "Network recovery reboot due to persistent failures"
    
    exit 1
}

# Function to attempt recovery using specified strategy
attempt_recovery() {
    local strategy="$1"
    local function_name="${RECOVERY_STRATEGIES[$strategy]}"
    
    if [ -n "$function_name" ]; then
        log_info "Attempting recovery strategy: $strategy"
        if $function_name; then
            log_success "Recovery successful using strategy: $strategy"
            return 0
        else
            log_warning "Recovery failed using strategy: $strategy"
            return 1
        fi
    else
        log_error "Unknown recovery strategy: $strategy"
        return 1
    fi
}

# Function to perform progressive recovery
perform_progressive_recovery() {
    local failure_count=$(get_failure_count)
    
    log_info "Starting progressive recovery (failure count: $failure_count)"
    
    # Determine recovery strategies based on failure count
    local strategies_to_try=()
    
    if [ "$failure_count" -lt "$MAX_CONSECUTIVE_FAILURES" ]; then
        # Standard recovery - try first 3 strategies
        strategies_to_try=("${RECOVERY_ORDER[@]:0:3}")
    else
        # Aggressive recovery - try all strategies
        strategies_to_try=("${RECOVERY_ORDER[@]}")
    fi
    
    # Try each strategy in order
    for strategy in "${strategies_to_try[@]}"; do
        if attempt_recovery "$strategy"; then
            return 0
        fi
    done
    
    log_error "All recovery strategies failed"
    return 1
}

# Function to handle connectivity issues
handle_connectivity_issue() {
    log_warning "Attempting connectivity recovery"
    
    if perform_progressive_recovery; then
        if check_internet; then
            log_success "Connectivity restored"
            reset_failure_count
            return 0
        fi
    fi
    
    log_error "Connectivity recovery failed"
    local new_count=$(track_failure)
    log_warning "Consecutive failure count: $new_count"
    
    if should_reboot; then
        perform_reboot
    fi
    
    return 1
}

# Function to handle interface down issues
handle_interface_issue() {
    log_error "wlan0 interface is DOWN or has no IP"
    
    if perform_progressive_recovery; then
        if check_wlan0; then
            log_success "Interface restored"
            reset_failure_count
            return 0
        fi
    fi
    
    log_error "Interface recovery failed"
    local new_count=$(track_failure)
    log_warning "Consecutive failure count: $new_count"
    
    if should_reboot; then
        perform_reboot
    fi
    
    return 1
}

# Main monitoring function
main() {
    log_info "=============================================="
    log_info "Network Monitor Starting"
    
    # Check if we're recovering from a reboot
    if check_reboot_marker; then
        log_info "System recovered from network reboot"
    fi
    
    # Check wlan0 status first
    if ! check_wlan0; then
        handle_interface_issue
        return $?
    fi
    
    # Interface is up, get IP and check connectivity
    local wlan0_ip=$(ip -4 addr show wlan0 | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
    log_success "wlan0 interface is UP with IP: $wlan0_ip"
    
    # Check internet connectivity
    if check_internet; then
        log_success "Internet connectivity confirmed"
        reset_failure_count
    else
        log_error "Internet connectivity failed"
        handle_connectivity_issue
        return $?
    fi
    
    log_info "Network monitoring check completed"
    log_info "----------------------------------------------"
    return 0
}

# Execute main function
main
exit $?