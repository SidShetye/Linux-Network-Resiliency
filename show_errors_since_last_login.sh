#!/usr/bin/env bash

# Script to show network errors since last login
# Uses centralized state management

# Source the centralized state manager
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/state_manager.sh"

# Function to show errors since last login
show_errors_since_last_login() {
    local last_login=$(get_last_login_time)
    
    if [ ! -f "$NETWORK_LOG_FILE" ]; then
        echo "No network log file found at: $NETWORK_LOG_FILE"
        return 1
    fi
    
    # Check if we have a valid last login time
    if [ "$last_login" = "0" ]; then
        echo "No previous login time recorded. Showing all recent errors:"
        # Show errors from last 7 days if no login time is available
        last_login=$(date -d '7 days ago' +%s)
    fi
    
    # Convert last login timestamp to readable format for user info
    local last_login_readable=$(date -d "@$last_login" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "unknown")
    echo "Showing network errors since last login ($last_login_readable):"
    echo "================================================================"
    
    # Filter log entries for errors since last login
    # Look for [ERROR] and [WARNING] entries with timestamps after last login
    awk -v last_login="$last_login" '
    /^\[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2} \[(ERROR|WARNING)\]/ {
        # Extract timestamp from log line
        datetime = $1 " " $2
        
        # Convert to epoch time
        cmd = "date -d \"" datetime "\" +%s 2>/dev/null"
        if ((cmd | getline epoch) > 0) {
            close(cmd)
            
            # Only show entries after last login
            if (epoch > last_login) {
                print
            }
        } else {
            close(cmd)
        }
    }' "$NETWORK_LOG_FILE"
    
    # Also check compressed log files for recent errors
    for compressed_log in "${NETWORK_LOG_FILE}".*.gz; do
        if [ -f "$compressed_log" ]; then
            zcat "$compressed_log" 2>/dev/null | awk -v last_login="$last_login" '
            /^\[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2} \[(ERROR|WARNING)\]/ {
                datetime = $1 " " $2
                cmd = "date -d \"" datetime "\" +%s 2>/dev/null"
                if ((cmd | getline epoch) > 0) {
                    close(cmd)
                    if (epoch > last_login) {
                        print
                    }
                } else {
                    close(cmd)
                }
            }'
        fi
    done
    
    echo "================================================================"
}

# Function to show summary of recent network issues
show_error_summary() {
    local last_login=$(get_last_login_time)
    local current_failures=$(get_failure_count)
    
    echo ""
    echo "Network Status Summary:"
    echo "======================"
    echo "Current consecutive failures: $current_failures"
    
    if [ "$current_failures" -gt 0 ]; then
        echo "⚠️  Network issues detected!"
        if should_reboot; then
            echo "🚨 System is scheduled for reboot due to persistent failures"
        fi
    else
        echo "✅ Network appears stable"
    fi
    
    # Count errors since last login
    if [ -f "$NETWORK_LOG_FILE" ]; then
        local error_count=$(awk -v last_login="$last_login" '
        /^\[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2} \[ERROR\]/ {
            datetime = $1 " " $2
            cmd = "date -d \"" datetime "\" +%s 2>/dev/null"
            if ((cmd | getline epoch) > 0) {
                close(cmd)
                if (epoch > last_login) {
                    count++
                }
            } else {
                close(cmd)
            }
        }
        END { print count+0 }' "$NETWORK_LOG_FILE")
        
        echo "Total errors since last login: $error_count"
    fi
    echo ""
}

# Main execution
main() {
    # Show errors since last login
    show_errors_since_last_login
    
    # Show summary
    show_error_summary
}

# Execute main function if script is run directly
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi
