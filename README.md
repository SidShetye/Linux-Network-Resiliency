# Network Monitor for Raspberry Pi

## Overview

The Network Monitor is a comprehensive network monitoring and recovery system for Raspberry Pi devices. It automatically detects network connectivity issues and performs progressive recovery actions, from simple interface restarts to complete system reboots when necessary.

## Architecture

The system consists of several components working together:

- **[`network_monitor.sh`](network_monitor.sh)** - Main monitoring script with progressive recovery strategies
- **[`state_manager.sh`](state_manager.sh)** - Centralized state management library
- **[`show_errors_since_last_login.sh`](show_errors_since_last_login.sh)** - Error reporting and status display
- **[`network-monitor.service`](network-monitor.service)** - Systemd service definition
- **[`network-monitor.timer`](network-monitor.timer)** - Systemd timer for automated execution

## Key Features

### 1. Progressive Recovery Strategy
The system implements a six-level recovery approach, escalating from least to most aggressive:

1. **Basic Interface Restart** - Simple interface down/up cycle
2. **DHCP Renewal** - Force new IP lease with timeout
3. **USB Reset** - Reset USB WiFi adapters (hardware-level)
4. **Module Reload** - Reload WiFi kernel modules
5. **WPA Supplicant Restart** - Restart authentication service
6. **Networking Service Restart** - Full networking stack restart

### 2. Intelligent Failure Tracking
- Tracks consecutive failures to escalate recovery methods
- Configurable thresholds for aggressive recovery and system reboot
- Automatic failure count reset upon successful recovery
- Persistent state management across reboots

### 3. Centralized State Management
All state is managed through [`state_manager.sh`](state_manager.sh):
- **State files**: `/home/sid/projects/uptime_monitor/state/`
- **Log files**: `/home/sid/projects/uptime_monitor/logs/`
- **Consistent API**: All scripts use the same functions for state management

### 4. Enhanced Diagnostics and Logging
- Structured logging with consistent format: `TIMESTAMP [LEVEL] MESSAGE`
- Automatic log rotation and compression (5MB limit)
- Detailed interface status reporting
- Multiple DNS server connectivity testing
- Error tracking and reporting since last login

### 5. Hardware-Level Recovery
- USB bus reset for USB WiFi adapters
- WiFi kernel module reloading (`brcmfmac`, `brcmutil`, `cfg80211`)
- Network interface flushing and reconfiguration

## Configuration

Edit these variables in [`state_manager.sh`](state_manager.sh) to customize behavior:

```bash
MAX_CONSECUTIVE_FAILURES=3    # Failures before aggressive reset
DHCP_TIMEOUT=30               # DHCP timeout in seconds
REBOOT_THRESHOLD=3            # Failures before system reboot
MAX_LOG_SIZE=5242880          # Log rotation size (5MB)
MAX_LOG_FILES=5               # Maximum old log files to keep
```

## Installation and Setup

### 1. Install as Systemd Service (Recommended)

Copy the service files and enable the timer:

```bash
# Copy service files to systemd directory
sudo cp /home/sid/projects/uptime_monitor/network-monitor.timer /etc/systemd/system/
sudo cp /home/sid/projects/uptime_monitor/network-monitor.service /etc/systemd/system/

# Reload systemd to recognize the changes
sudo systemctl daemon-reload

# Stop any existing timer
sudo systemctl stop network-monitor.timer

# Start and enable the timer
sudo systemctl start network-monitor.timer
sudo systemctl enable network-monitor.timer
```

### 2. Manual Installation (Alternative)

If you prefer cron-based execution:

```bash
# Make scripts executable
chmod +x /home/sid/projects/uptime_monitor/network_monitor.sh
chmod +x /home/sid/projects/uptime_monitor/show_errors_since_last_login.sh

# Add to crontab
crontab -e
# Add this line:
*/15 * * * * /home/sid/projects/uptime_monitor/network_monitor.sh
```

### 3. Setup Login Error Display

Add to your shell profile (`.bashrc` or `.profile`):

```bash
# Show network errors since last login
if [ -f ~/projects/uptime_monitor/show_errors_since_last_login.sh ]; then
    # Update last login time
    echo $(date +%s) > ~/projects/uptime_monitor/state/last_login_time
    
    # Show errors since last login
    ~/projects/uptime_monitor/show_errors_since_last_login.sh
fi
```

## Verification and Monitoring

### Check Service Status

```bash
# Check timer status
sudo systemctl status network-monitor.timer

# List all timers to see when yours will run next
systemctl list-timers network-monitor.timer

# Check if the service runs immediately
sudo systemctl status network-monitor.service

# View recent logs
journalctl -u network-monitor.service -f
```

### Monitor Network Status

```bash
# Check current failure count
cat /home/sid/projects/uptime_monitor/state/network_failures

# View recent network logs
tail -f /home/sid/projects/uptime_monitor/logs/network_monitor.log

# Show errors since last login
/home/sid/projects/uptime_monitor/show_errors_since_last_login.sh

# Reset failure count manually if needed
rm -f /home/sid/projects/uptime_monitor/state/network_failures
```

## Recovery Mechanisms Explained

### Standard Recovery (Failures < 3)
For initial failures, the system tries basic recovery methods:
- Interface restart
- DHCP renewal
- USB bus reset (if applicable)

### Aggressive Recovery (Failures ≥ 3)
When failures persist, all recovery strategies are attempted:
- All standard methods
- Kernel module reload
- WPA supplicant restart with cleanup
- Full networking service restart

### System Reboot (Last Resort)
After reaching the reboot threshold:
- Creates reboot marker for tracking
- Graceful shutdown with filesystem sync
- Automatic recovery confirmation after reboot

## Failure Scenarios Addressed

### 1. "Interface UP but no IP"
**Recovery sequence:**
1. DHCP renewal with timeout
2. USB bus reset (if USB WiFi adapter)
3. Kernel module reload
4. Enhanced service restarts
5. System reboot if persistent

### 2. Driver/Hardware Issues
- USB bus reset for USB adapters
- Kernel module reload for driver issues
- Complete hardware reset via reboot

### 3. DHCP/Network Configuration Issues
- Forced DHCP lease renewal
- Network configuration flushing
- Service restart with cleanup

### 4. Authentication Issues
- WPA supplicant restart with socket cleanup
- Process cleanup and restart
- Configuration reload

## File Structure

```
projects/uptime_monitor/
├── network_monitor.sh              # Main monitoring script
├── state_manager.sh                # Centralized state management
├── show_errors_since_last_login.sh # Error display script
├── network-monitor.service         # Systemd service definition
├── network-monitor.timer           # Systemd timer configuration
├── state/                          # Centralized state directory
│   ├── network_failures            # Failure count tracking
│   ├── last_login_time             # Login time tracking
│   └── network_reboot_marker       # Reboot marker
├── logs/                           # Centralized log directory
│   └── network_monitor.log         # Structured log file
└── README.md                       # This documentation
```

## Testing

### Manual Test
```bash
# Run once manually to test
cd /home/sid/projects/uptime_monitor
./network_monitor.sh

# Check the log for new entries
tail -f logs/network_monitor.log
```

### Simulate Failure
```bash
# Temporarily disable interface to test recovery
sudo ip link set wlan0 down

# Run the script
./network_monitor.sh

# Check if it recovered
ip addr show wlan0
```

### Test Error Display
```bash
# Show current network status and errors
./show_errors_since_last_login.sh
```

## Troubleshooting

### Script Not Working
1. Check permissions: `ls -la network_monitor.sh`
2. Verify sudo access: `sudo -l`
3. Check log file: `tail -20 logs/network_monitor.log`
4. Verify state directory exists: `ls -la state/`

### Frequent Reboots
1. Increase `REBOOT_THRESHOLD` value in [`state_manager.sh`](state_manager.sh)
2. Check for hardware issues
3. Verify WiFi configuration
4. Monitor system logs: `journalctl -f`

### USB Reset Not Working
1. Verify USB WiFi adapter: `lsusb`
2. Check device path: `ls -la /sys/class/net/wlan0/device/`
3. Ensure proper permissions for USB control

### Service Not Starting
1. Check service status: `sudo systemctl status network-monitor.service`
2. Verify file paths in service file
3. Check systemd logs: `journalctl -u network-monitor.service`

## Log Analysis

### Useful Commands
```bash
# Count recent failures
grep "Consecutive failure count" logs/network_monitor.log | tail -10

# Check recovery success rate
grep -E "\[(SUCCESS|ERROR)\]" logs/network_monitor.log | tail -20

# Monitor reboot frequency
grep "network reboot" logs/network_monitor.log

# Show all errors since specific date
awk '/^2024-01-15.*\[ERROR\]/' logs/network_monitor.log
```

### Log Format
All log entries follow the structured format:
```
YYYY-MM-DD HH:MM:SS [LEVEL] MESSAGE
```

Levels include: `INFO`, `SUCCESS`, `WARNING`, `ERROR`

## Security Considerations

- Script requires sudo access for network operations
- USB device manipulation requires elevated privileges
- System reboot capability should be used carefully
- Consider firewall rules for network operations
- State files are stored in user directory for security

## Performance Impact

- Minimal CPU usage during normal operation
- Increased resource usage during recovery operations
- Longer execution time due to enhanced diagnostics
- Brief network interruption during aggressive recovery
- Automatic log rotation prevents disk space issues

## Backup and Recovery

### Before Deployment
```bash
# Backup current network configuration
sudo cp /etc/wpa_supplicant/wpa_supplicant.conf /etc/wpa_supplicant/wpa_supplicant.conf.backup
sudo cp /etc/dhcpcd.conf /etc/dhcpcd.conf.backup
```

### Emergency Recovery
If the system causes issues:
```bash
# Stop the service
sudo systemctl stop network-monitor.timer
sudo systemctl disable network-monitor.timer

# Reset failure tracking
rm -f /home/sid/projects/uptime_monitor/state/network_failures
rm -f /home/sid/projects/uptime_monitor/state/network_reboot_marker

# Restart networking manually
sudo systemctl restart networking
```

## Maintenance

### Regular Tasks
- Monitor log file size and rotation
- Review failure patterns in logs
- Update thresholds based on experience
- Test recovery mechanisms periodically
- Check state directory permissions

### Updates and Modifications
When modifying the scripts:
1. Test changes manually first
2. Update configuration in [`state_manager.sh`](state_manager.sh)
3. Restart the service: `sudo systemctl restart network-monitor.timer`
4. Monitor logs for any issues

## Support

For issues or improvements:
1. Check the logs first: `tail -50 logs/network_monitor.log`
2. Verify configuration in [`state_manager.sh`](state_manager.sh)
3. Test individual recovery functions manually
4. Review system logs: `journalctl -f`

This network monitoring system provides robust, automated network recovery for Raspberry Pi devices with comprehensive logging and state management.