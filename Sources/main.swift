import AppKit
import Darwin

// MARK: - Data Types

struct TunnelInfo {
    let name: String
    let status: String
    let serviceID: String
}

struct InterfaceStats {
    let name: String
    let bytesIn: UInt64
    let bytesOut: UInt64
}

// MARK: - Shell Helper

func shell(_ command: String) -> String {
    let process = Process()
    let pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/bin/sh")
    process.arguments = ["-c", command]
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    try? process.run()
    process.waitUntilExit()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    return String(data: data, encoding: .utf8) ?? ""
}

// MARK: - WireGuard Detection

func getWireGuardTunnels() -> [TunnelInfo] {
    let output = shell("scutil --nc list 2>/dev/null")
    var tunnels: [TunnelInfo] = []
    for line in output.components(separatedBy: "\n") {
        guard line.contains("com.wireguard.macos") else { continue }
        // Parse: * (Connected)      UUID VPN (com.wireguard.macos) "Name"
        let connected = line.contains("(Connected)")
        let disconnected = line.contains("(Disconnected)")
        let status = connected ? "Connected" : (disconnected ? "Disconnected" : "Unknown")

        // Extract name from quotes
        var name = "Unknown"
        if let firstQuote = line.firstIndex(of: "\"") {
            let afterQuote = line.index(after: firstQuote)
            if let lastQuote = line[afterQuote...].firstIndex(of: "\"") {
                name = String(line[afterQuote..<lastQuote])
            }
        }

        // Extract UUID
        let parts = line.split(separator: " ")
        var serviceID = ""
        for part in parts {
            let s = String(part)
            if s.count == 36 && s.contains("-") {
                serviceID = s
                break
            }
        }

        tunnels.append(TunnelInfo(name: name, status: status, serviceID: serviceID))
    }
    return tunnels
}

/// Find utun interfaces that have an assigned IPv4 (point-to-point) — these are WireGuard tunnels
func getWireGuardInterfaces() -> [String] {
    let output = shell("ifconfig 2>/dev/null")
    var interfaces: [String] = []
    var currentInterface = ""

    for line in output.components(separatedBy: "\n") {
        if !line.hasPrefix("\t") && !line.hasPrefix(" ") && line.contains(":") {
            let name = String(line.split(separator: ":").first ?? "")
            if name.hasPrefix("utun") {
                currentInterface = name
            } else {
                currentInterface = ""
            }
        } else if !currentInterface.isEmpty && line.contains("inet ") && line.contains("-->") {
            interfaces.append(currentInterface)
        }
    }
    return interfaces
}

func getInterfaceStats(for interfaceName: String) -> InterfaceStats? {
    let output = shell("netstat -ib -I \(interfaceName) 2>/dev/null")
    let lines = output.components(separatedBy: "\n")
    // Find the line with <Link#...> which has raw byte counts
    for line in lines {
        guard line.hasPrefix(interfaceName) && line.contains("<Link#") else { continue }
        let cols = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        // Link-level row has no Address: Name Mtu Network Ipkts Ierrs Ibytes Opkts Oerrs Obytes Coll
        guard cols.count >= 10 else { continue }
        if let bytesIn = UInt64(cols[5]), let bytesOut = UInt64(cols[8]) {
            return InterfaceStats(name: interfaceName, bytesIn: bytesIn, bytesOut: bytesOut)
        }
    }
    return nil
}

// MARK: - Formatting

func formatBytes(_ bytes: UInt64) -> String {
    let units = ["B", "KB", "MB", "GB", "TB"]
    var value = Double(bytes)
    var unitIndex = 0
    while value >= 1024 && unitIndex < units.count - 1 {
        value /= 1024
        unitIndex += 1
    }
    if unitIndex == 0 {
        return "\(bytes) B"
    }
    return String(format: "%.1f %@", value, units[unitIndex])
}

func formatSpeed(_ bytesPerSec: Double) -> String {
    if bytesPerSec < 1 { return "0 B/s" }
    let units = ["B/s", "KB/s", "MB/s", "GB/s"]
    var value = bytesPerSec
    var unitIndex = 0
    while value >= 1024 && unitIndex < units.count - 1 {
        value /= 1024
        unitIndex += 1
    }
    return String(format: "%.1f %@", value, units[unitIndex])
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var timer: Timer?
    var prevStats: InterfaceStats?
    var prevTime: Date?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "VPN —"
        statusItem.button?.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)

        updateStatus()
        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            self?.updateStatus()
        }
    }

    func updateStatus() {
        let tunnels = getWireGuardTunnels()
        let interfaces = getWireGuardInterfaces()
        let connectedTunnels = tunnels.filter { $0.status == "Connected" }

        // Get stats for all WireGuard interfaces
        var totalIn: UInt64 = 0
        var totalOut: UInt64 = 0
        var currentStats: InterfaceStats?

        for iface in interfaces {
            if let stats = getInterfaceStats(for: iface) {
                totalIn += stats.bytesIn
                totalOut += stats.bytesOut
                if currentStats == nil {
                    currentStats = stats
                } else {
                    currentStats = InterfaceStats(
                        name: "all",
                        bytesIn: totalIn,
                        bytesOut: totalOut
                    )
                }
            }
        }

        // Calculate speed
        var speedIn = 0.0
        var speedOut = 0.0
        let now = Date()
        if let prev = prevStats, let prevT = prevTime {
            let elapsed = now.timeIntervalSince(prevT)
            if elapsed > 0 {
                speedIn = Double(totalIn.subtractingReportingOverflow(prev.bytesIn).partialValue) / elapsed
                speedOut = Double(totalOut.subtractingReportingOverflow(prev.bytesOut).partialValue) / elapsed
            }
        }
        prevStats = InterfaceStats(name: "all", bytesIn: totalIn, bytesOut: totalOut)
        prevTime = now

        // Update menu bar title
        if connectedTunnels.isEmpty {
            statusItem.button?.title = "VPN Off"
        } else {
            statusItem.button?.title = "↓\(formatBytes(totalIn)) ↑\(formatBytes(totalOut))"
        }

        // Build menu
        let menu = NSMenu()

        // Tunnel info
        if tunnels.isEmpty {
            menu.addItem(NSMenuItem(title: "No WireGuard tunnels found", action: nil, keyEquivalent: ""))
        } else {
            for tunnel in tunnels {
                let icon = tunnel.status == "Connected" ? "🟢" : "🔴"
                let item = NSMenuItem(title: "\(icon) \(tunnel.name) — \(tunnel.status)", action: nil, keyEquivalent: "")
                menu.addItem(item)
            }
        }

        menu.addItem(NSMenuItem.separator())

        // Stats
        if !interfaces.isEmpty && !connectedTunnels.isEmpty {
            let ifaceLabel = interfaces.count == 1 ? "Interface: \(interfaces[0])" : "Interfaces: \(interfaces.joined(separator: ", "))"
            menu.addItem(NSMenuItem(title: ifaceLabel, action: nil, keyEquivalent: ""))
            menu.addItem(NSMenuItem.separator())

            menu.addItem(NSMenuItem(title: "↓ Downloaded: \(formatBytes(totalIn))", action: nil, keyEquivalent: ""))
            menu.addItem(NSMenuItem(title: "↑ Uploaded:     \(formatBytes(totalOut))", action: nil, keyEquivalent: ""))
            menu.addItem(NSMenuItem(title: "↕ Total:            \(formatBytes(totalIn + totalOut))", action: nil, keyEquivalent: ""))
            menu.addItem(NSMenuItem.separator())

            menu.addItem(NSMenuItem(title: "↓ Speed: \(formatSpeed(speedIn))", action: nil, keyEquivalent: ""))
            menu.addItem(NSMenuItem(title: "↑ Speed: \(formatSpeed(speedOut))", action: nil, keyEquivalent: ""))
        } else {
            menu.addItem(NSMenuItem(title: "No active tunnel", action: nil, keyEquivalent: ""))
        }

        menu.addItem(NSMenuItem.separator())

        // Quit
        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    @objc func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}

// MARK: - Main

// Detach from terminal so closing it won't kill the app
if CommandLine.arguments.last != "--daemon" {
    // Resolve full path of the binary (handles symlinks and PATH lookup)
    let selfPath = shell("which \(CommandLine.arguments[0]) 2>/dev/null || echo \(CommandLine.arguments[0])").trimmingCharacters(in: .whitespacesAndNewlines)
    let resolved = shell("readlink -f \(selfPath) 2>/dev/null || echo \(selfPath)").trimmingCharacters(in: .whitespacesAndNewlines)
    let process = Process()
    process.executableURL = URL(fileURLWithPath: resolved)
    process.arguments = ["--daemon"]
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try? process.run()
    exit(0)
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
