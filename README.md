# Enhanced Network Monitor for Raspberry Pi

## Overview

The Enhanced Network Monitor (`network_monitor_enhanced.sh`) is an advanced version of the original network monitoring script designed to handle stubborn network failures that require more aggressive recovery mechanisms, including hardware-level resets and system reboots.

## Key Improvements

### 1. Multi-Level Recovery Strategy
- **Level 1**: Standard interface restart
- **Level 2**: DHCP renewal with timeout
- **Level 3**: USB bus reset (for USB WiFi adapters)
- **Level 4**: Kernel module reload
- **Level 5**: Enhanced service restarts
- **Level 6**: System reboot (last resort)

### 2. Failure Tracking
- Tracks consecutive failures to escalate recovery methods
- Configurable thresholds for aggressive recovery and system reboot
- Automatic failure count reset upon successful recovery

### 3. Enhanced Diagnostics
- Detailed interface status logging
- Multiple DNS server connectivity testing
- Comprehensive error reporting with emojis for easy log parsing

### 4. Hardware-Level Recovery
- USB bus reset for USB WiFi adapters
- WiFi kernel module reloading (brcmfmac, brcmutil, cfg80211)
- Network interface flushing and reconfiguration

## Configuration

Edit these variables at the top of the script to customize behavior:

```bash
MAX_CONSECUTIVE_FAILURES=3    # Failures before aggressive reset
DHCP_TIMEOUT=30               # DHCP timeout in seconds
REBOOT_THRESHOLD=5            # Failures before system reboot
```

## Installation

1. **Backup your current script:**
   ```bash
   cp network_monitor.sh network_monitor_original.sh
   ```

2. **Copy the enhanced script:**
   ```bash
   cp network_monitor_enhanced.sh network_monitor.sh
   ```

3. **Make it executable:**
   ```bash
   chmod +x network_monitor.sh
   ```

4. **Update your crontab (if using cron):**
   ```bash
   crontab -e
   # Add or modify the line:
   */15 * * * * /home/sid/projects/uptime_monitor/network_monitor.sh
   ```

## Recovery Mechanisms Explained

### Standard Recovery (Original Methods)
- Interface up/down cycling
- wpa_supplicant service restart
- networking service restart

### Enhanced Recovery (New Methods)

#### DHCP Renewal
- Releases current DHCP lease
- Requests new lease with configurable timeout
- Handles DHCP server issues and IP conflicts

#### USB Bus Reset
- Detects USB WiFi adapters automatically
- Unbinds and rebinds USB device
- Effective for hardware-level USB issues

#### Kernel Module Reload
- Unloads WiFi kernel modules
- Reloads modules in correct order
- Handles driver-level issues

#### Enhanced Service Restarts
- Kills stale processes
- Clears socket files
- Flushes network configurations
- Extended wait times for proper initialization

#### System Reboot
- Last resort after configurable failure threshold
- Creates reboot marker for tracking
- Graceful shutdown with filesystem sync

## Failure Scenarios Addressed

### 1. "Interface UP but no IP" (Your Issue)
**Recovery sequence:**
1. DHCP renewal with timeout
2. USB bus reset (if applicable)
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

### 4. Persistent Failures
- Automatic escalation to system reboot
- Failure tracking prevents infinite loops
- Recovery confirmation and reset

## Monitoring and Logs

### Log Enhancements
- Emoji indicators for quick visual parsing
- Detailed diagnostic information
- Failure count tracking
- Recovery method identification

### Log Rotation
- Automatic compression of old logs
- Configurable retention policy
- Size-based rotation (5MB default)

### Key Log Indicators
- ✅ Success indicators
- ❌ Failure indicators  
- ⚠️ Warning/recovery indicators
- 🔄 Process indicators
- 🚨 Critical alerts
- 📊 Diagnostic information

## Testing the Enhanced Script

### Manual Test
```bash
# Run once manually to test
./network_monitor_enhanced.sh

# Check the log for new entries
tail -f network_monitor.log
```

### Simulate Failure
```bash
# Temporarily disable interface to test recovery
sudo ip link set wlan0 down

# Run the script
./network_monitor_enhanced.sh

# Check if it recovered
ip addr show wlan0
```

### Monitor Failure Count
```bash
# Check current failure count
cat /tmp/network_failures

# Reset failure count manually if needed
rm -f /tmp/network_failures
```

## Troubleshooting

### Script Not Working
1. Check permissions: `ls -la network_monitor_enhanced.sh`
2. Verify sudo access: `sudo -l`
3. Check log file: `tail -20 network_monitor.log`

### Frequent Reboots
1. Increase `REBOOT_THRESHOLD` value
2. Check for hardware issues
3. Verify WiFi configuration
4. Monitor system logs: `journalctl -f`

### USB Reset Not Working
1. Verify USB WiFi adapter: `lsusb`
2. Check device path: `ls -la /sys/class/net/wlan0/device/`
3. Ensure proper permissions for USB control

## Comparison with Original Script

| Feature | Original | Enhanced |
|---------|----------|----------|
| Recovery Methods | 3 basic | 6+ advanced |
| Failure Tracking | None | Comprehensive |
| Hardware Reset | No | Yes (USB/modules) |
| DHCP Handling | Basic | Advanced with timeout |
| Diagnostics | Minimal | Detailed |
| Reboot Capability | No | Yes (configurable) |
| Log Quality | Basic | Enhanced with emojis |

## Security Considerations

- Script requires sudo access for network operations
- USB device manipulation requires elevated privileges
- System reboot capability should be used carefully
- Consider firewall rules for network operations

## Performance Impact

- Minimal CPU usage during normal operation
- Increased resource usage during recovery operations
- Longer execution time due to enhanced diagnostics
- Network interruption during aggressive recovery

## Backup and Recovery

### Before Deployment
```bash
# Backup current configuration
cp /etc/wpa_supplicant/wpa_supplicant.conf /etc/wpa_supplicant/wpa_supplicant.conf.backup
cp /etc/dhcpcd.conf /etc/dhcpcd.conf.backup
```

### Emergency Recovery
If the enhanced script causes issues:
```bash
# Restore original script
cp network_monitor_original.sh network_monitor.sh

# Reset failure tracking
rm -f /tmp/network_failures /tmp/network_reboot_marker

# Restart networking manually
sudo systemctl restart networking
```

## Support and Maintenance

### Regular Maintenance
- Monitor log file size and rotation
- Review failure patterns in logs
- Update thresholds based on experience
- Test recovery mechanisms periodically

### Log Analysis
```bash
# Count recent failures
grep "Consecutive failure count" network_monitor.log | tail -10

# Check recovery success rate
grep -E "(✅|❌)" network_monitor.log | tail -20

# Monitor reboot frequency
grep "network reboot" network_monitor.log
```

This enhanced script should handle the persistent "interface UP but no IP" failures you experienced by implementing multiple recovery strategies and ultimately rebooting the system when all else fails.