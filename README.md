# wireguard-monitor-menubar

A lightweight macOS menu bar app that shows your WireGuard VPN usage (download/upload) at a glance.

## Features

- Shows live download/upload totals in the menu bar
- Auto-detects WireGuard tunnels and their connection status
- Displays transfer speed (updated every 10s)
- Dropdown with detailed stats per tunnel
- No sudo required — reads interface stats from `netstat`
- Zero dependencies — pure Swift + AppKit

## Install

### Homebrew

```bash
brew install elmanlucas/tap/wireguard-monitor-menubar
```

### Manual

```bash
git clone https://github.com/elmanlucas/wireguard-monitor-menubar.git
cd wireguard-monitor-menubar
make install
```

## Usage

```bash
wireguard-monitor-menubar
```

The app runs in the menu bar. Click the stats to see detailed info. Select **Quit** to exit.

### Start on login

```bash
brew services start wireguard-monitor-menubar
```

Or manually copy the LaunchAgent:

```bash
cp com.elman.wireguard-monitor.plist ~/Library/LaunchAgents/
launchctl load ~/Library/LaunchAgents/com.elman.wireguard-monitor.plist
```

## Requirements

- macOS 12+
- WireGuard app installed (App Store version)

## License

MIT
