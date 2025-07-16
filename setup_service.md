
## Commands to Install the Service and Timer

## Step-by-Step Deployment Commands

1. Copy the files to systemd directory
2. Reload systemd to recognize the changes
3. Stop the current timer (if it's running)
4. Start the updated timer
5. Enable the timer to start automatically on boot

As commands to copy-paste ...

```bash
sudo cp /home/sid/projects/uptime_monitor/network-monitor.timer /etc/systemd/system/
sudo cp /home/sid/projects/uptime_monitor/network-monitor.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl stop network-monitor.timer
sudo systemctl start network-monitor.timer
sudo systemctl enable network-monitor.timer
```

## Verification Commands

- Check timer status
`sudo systemctl status network-monitor.timer`

- List all timers to see when yours will run next
`systemctl list-timers network-monitor.timer`

- Check if the service runs immediately (due to OnStartupSec=0)
`sudo systemctl status network-monitor.service`

- View recent logs
`journalctl -u network-monitor.service -f`