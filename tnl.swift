import Cocoa
import ServiceManagement

let configPath = NSString(string: "~/.config/tnl/config.json").expandingTildeInPath

struct TunnelConfig: Codable {
    var host: String
    var ports: [Int]
    var connectOnLaunch: Bool
    var launchAtLogin: Bool

    init(host: String, ports: [Int], connectOnLaunch: Bool = false, launchAtLogin: Bool = false) {
        self.host = host
        self.ports = ports
        self.connectOnLaunch = connectOnLaunch
        self.launchAtLogin = launchAtLogin
    }
}

func loadConfig() -> TunnelConfig {
    let defaults = TunnelConfig(host: "chopper.local", ports: [3000, 3001, 3002, 54321, 54421, 54422, 54323])
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: configPath)),
          let config = try? JSONDecoder().decode(TunnelConfig.self, from: data) else {
        return defaults
    }
    return config
}

func saveConfig(_ config: TunnelConfig) {
    let dir = (configPath as NSString).deletingLastPathComponent
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    if let data = try? JSONEncoder().encode(config) {
        try? data.write(to: URL(fileURLWithPath: configPath))
    }
}

func setLaunchAtLogin(_ enabled: Bool) {
    if #available(macOS 13.0, *) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // silently fail — user can toggle in System Settings
        }
    }
}

class SettingsWindow: NSWindow {
    var hostField: NSTextField!
    var portsTextView: NSTextView!
    var connectOnLaunchBtn: NSButton!
    var launchAtLoginBtn: NSButton!
    var onSave: ((TunnelConfig) -> Void)?

    init(config: TunnelConfig, onSave: @escaping (TunnelConfig) -> Void) {
        self.onSave = onSave
        super.init(contentRect: NSRect(x: 0, y: 0, width: 360, height: 320),
                   styleMask: [.titled, .closable], backing: .buffered, defer: false)
        title = "TNL Settings"
        isReleasedWhenClosed = false
        center()

        let content = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: 320))

        let hostLabel = NSTextField(labelWithString: "Host:")
        hostLabel.frame = NSRect(x: 20, y: 275, width: 50, height: 20)
        content.addSubview(hostLabel)

        hostField = NSTextField(string: config.host)
        hostField.frame = NSRect(x: 80, y: 272, width: 260, height: 24)
        content.addSubview(hostField)

        let portsLabel = NSTextField(labelWithString: "Ports:")
        portsLabel.frame = NSRect(x: 20, y: 230, width: 50, height: 20)
        content.addSubview(portsLabel)

        let scrollView = NSScrollView(frame: NSRect(x: 80, y: 130, width: 260, height: 120))
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder

        portsTextView = NSTextView(frame: NSRect(x: 0, y: 0, width: 260, height: 120))
        portsTextView.isEditable = true
        portsTextView.isRichText = false
        portsTextView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        portsTextView.string = config.ports.map(String.init).joined(separator: "\n")
        portsTextView.textContainerInset = NSSize(width: 4, height: 4)

        scrollView.documentView = portsTextView
        content.addSubview(scrollView)

        let hint = NSTextField(labelWithString: "One port per line")
        hint.frame = NSRect(x: 80, y: 110, width: 260, height: 16)
        hint.font = NSFont.systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
        content.addSubview(hint)

        connectOnLaunchBtn = NSButton(checkboxWithTitle: "Connect automatically when app opens", target: nil, action: nil)
        connectOnLaunchBtn.frame = NSRect(x: 20, y: 75, width: 320, height: 20)
        connectOnLaunchBtn.state = config.connectOnLaunch ? .on : .off
        content.addSubview(connectOnLaunchBtn)

        launchAtLoginBtn = NSButton(checkboxWithTitle: "Start at login", target: nil, action: nil)
        launchAtLoginBtn.frame = NSRect(x: 20, y: 50, width: 320, height: 20)
        launchAtLoginBtn.state = config.launchAtLogin ? .on : .off
        content.addSubview(launchAtLoginBtn)

        let saveBtn = NSButton(title: "Save", target: self, action: #selector(save))
        saveBtn.frame = NSRect(x: 250, y: 15, width: 90, height: 30)
        saveBtn.bezelStyle = .rounded
        saveBtn.keyEquivalent = "\r"
        content.addSubview(saveBtn)

        contentView = content
    }

    @objc func save() {
        let host = hostField.stringValue.trimmingCharacters(in: .whitespaces)
        let ports = portsTextView.string
            .split(whereSeparator: { $0.isNewline || $0 == "," })
            .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }

        guard !host.isEmpty, !ports.isEmpty else { return }

        let connectOnLaunch = connectOnLaunchBtn.state == .on
        let launchAtLogin = launchAtLoginBtn.state == .on

        let config = TunnelConfig(host: host, ports: ports, connectOnLaunch: connectOnLaunch, launchAtLogin: launchAtLogin)
        saveConfig(config)
        setLaunchAtLogin(launchAtLogin)
        onSave?(config)
        close()
    }
}

class TunnelApp: NSObject, NSApplicationDelegate {
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    var tunnelProcess: Process?
    var menu: NSMenu!
    var config: TunnelConfig!
    var settingsWindow: SettingsWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        config = loadConfig()
        statusItem.button?.title = "⚡️"
        buildMenu()
        statusItem.menu = menu

        if config.connectOnLaunch {
            connect()
        }
    }

    func buildMenu() {
        menu = NSMenu()

        if tunnelProcess != nil {
            let item = NSMenuItem(title: "Connected to \(config.host)", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)

            let portsItem = NSMenuItem(title: "Ports: \(config.ports.map(String.init).joined(separator: ", "))", action: nil, keyEquivalent: "")
            portsItem.isEnabled = false
            menu.addItem(portsItem)

            menu.addItem(NSMenuItem.separator())
            menu.addItem(NSMenuItem(title: "Disconnect", action: #selector(disconnect), keyEquivalent: "d"))
        } else {
            let item = NSMenuItem(title: "Disconnected", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
            menu.addItem(NSMenuItem.separator())
            menu.addItem(NSMenuItem(title: "Connect", action: #selector(connect), keyEquivalent: "c"))
        }

        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))
    }

    @objc func connect() {
        guard tunnelProcess == nil else { return }

        var args = ["-N",
                    "-o", "ExitOnForwardFailure=no",
                    "-o", "ServerAliveInterval=15",
                    "-o", "ServerAliveCountMax=3"]

        for port in config.ports {
            args += ["-L", "\(port):localhost:\(port)"]
        }
        args.append(config.host)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        process.arguments = args
        process.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                self?.tunnelProcess = nil
                self?.statusItem.button?.title = "⚡️"
                self?.buildMenu()
            }
        }

        do {
            try process.run()
            tunnelProcess = process
            statusItem.button?.title = "🟢"
            buildMenu()
        } catch {
            let alert = NSAlert()
            alert.messageText = "Failed to start tunnel"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    @objc func disconnect() {
        tunnelProcess?.terminate()
        tunnelProcess = nil
        statusItem.button?.title = "⚡️"
        buildMenu()
    }

    @objc func openSettings() {
        settingsWindow = SettingsWindow(config: config) { [weak self] newConfig in
            self?.config = newConfig
            self?.buildMenu()
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func quit() {
        tunnelProcess?.terminate()
        NSApp.terminate(nil)
    }
}

let app = NSApplication.shared
let delegate = TunnelApp()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
