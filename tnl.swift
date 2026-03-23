import Cocoa
import ServiceManagement

let currentVersion = "1.1.1"
let repoOwner = "danpaulson"
let repoName = "tnl"
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

struct GitHubRelease: Codable {
    let tag_name: String
    let assets: [GitHubAsset]
}

struct GitHubAsset: Codable {
    let name: String
    let browser_download_url: String
}

func compareVersions(_ a: String, _ b: String) -> ComparisonResult {
    let aParts = a.replacingOccurrences(of: "v", with: "").split(separator: ".").compactMap { Int($0) }
    let bParts = b.replacingOccurrences(of: "v", with: "").split(separator: ".").compactMap { Int($0) }
    for i in 0..<max(aParts.count, bParts.count) {
        let aVal = i < aParts.count ? aParts[i] : 0
        let bVal = i < bParts.count ? bParts[i] : 0
        if aVal < bVal { return .orderedAscending }
        if aVal > bVal { return .orderedDescending }
    }
    return .orderedSame
}

class Updater {
    static func checkForUpdate(silent: Bool = true, completion: @escaping (GitHubRelease?) -> Void) {
        let urlStr = "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases/latest"
        guard let url = URL(string: urlStr) else { completion(nil); return }

        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data = data,
                  let release = try? JSONDecoder().decode(GitHubRelease.self, from: data) else {
                DispatchQueue.main.async {
                    if !silent {
                        let alert = NSAlert()
                        alert.messageText = "Update Check Failed"
                        alert.informativeText = "Could not reach GitHub."
                        alert.runModal()
                    }
                    completion(nil)
                }
                return
            }

            let remote = release.tag_name
            if compareVersions(currentVersion, remote) == .orderedAscending {
                DispatchQueue.main.async { completion(release) }
            } else {
                DispatchQueue.main.async {
                    if !silent {
                        let alert = NSAlert()
                        alert.messageText = "You're up to date"
                        alert.informativeText = "TNL v\(currentVersion) is the latest version."
                        alert.runModal()
                    }
                    completion(nil)
                }
            }
        }.resume()
    }

    static func promptAndUpdate(release: GitHubRelease) {
        let version = release.tag_name.replacingOccurrences(of: "v", with: "")
        let alert = NSAlert()
        alert.messageText = "Update Available"
        alert.informativeText = "TNL v\(version) is available. You have v\(currentVersion).\n\nThe app will quit and relaunch after updating."
        alert.addButton(withTitle: "Update")
        alert.addButton(withTitle: "Later")

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        guard let dmgAsset = release.assets.first(where: { $0.name.hasSuffix(".dmg") }),
              let dmgURL = URL(string: dmgAsset.browser_download_url) else {
            let err = NSAlert()
            err.messageText = "Update Failed"
            err.informativeText = "No DMG found in the release."
            err.runModal()
            return
        }

        let downloadAlert = NSAlert()
        downloadAlert.messageText = "Downloading update..."
        downloadAlert.informativeText = "Please wait."
        downloadAlert.addButton(withTitle: "OK")
        downloadAlert.buttons.first?.isHidden = true
        let window = downloadAlert.window
        downloadAlert.layout()
        window.center()
        window.makeKeyAndOrderFront(nil)

        URLSession.shared.downloadTask(with: dmgURL) { tempURL, _, error in
            DispatchQueue.main.async { window.close() }

            guard let tempURL = tempURL, error == nil else {
                DispatchQueue.main.async {
                    let err = NSAlert()
                    err.messageText = "Download Failed"
                    err.informativeText = error?.localizedDescription ?? "Unknown error"
                    err.runModal()
                }
                return
            }

            DispatchQueue.main.async {
                Self.installUpdate(dmgPath: tempURL.path)
            }
        }.resume()
    }

    static func installUpdate(dmgPath: String) {
        let mountPoint = "/tmp/tnl-update-\(ProcessInfo.processInfo.processIdentifier)"
        try? FileManager.default.createDirectory(atPath: mountPoint, withIntermediateDirectories: true)

        let mount = Process()
        mount.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        mount.arguments = ["attach", dmgPath, "-mountpoint", mountPoint, "-nobrowse", "-quiet"]
        try? mount.run()
        mount.waitUntilExit()

        guard mount.terminationStatus == 0 else {
            let alert = NSAlert()
            alert.messageText = "Update Failed"
            alert.informativeText = "Could not mount the DMG."
            alert.runModal()
            return
        }

        let appSource = "\(mountPoint)/TNL.app"
        guard let appBundle = Bundle.main.bundlePath as String?,
              FileManager.default.fileExists(atPath: appSource) else {
            let detach = Process()
            detach.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
            detach.arguments = ["detach", mountPoint, "-quiet"]
            try? detach.run()
            let alert = NSAlert()
            alert.messageText = "Update Failed"
            alert.informativeText = "Could not find TNL.app in the DMG."
            alert.runModal()
            return
        }

        let appDest = appBundle

        // Write a small script that waits for us to quit, replaces the app, relaunches, and cleans up
        let script = """
        #!/bin/bash
        sleep 1
        rm -rf "\(appDest)"
        cp -R "\(appSource)" "\(appDest)"
        hdiutil detach "\(mountPoint)" -quiet
        rm -f "\(dmgPath)"
        open "\(appDest)"
        """

        let scriptPath = "/tmp/tnl-update.sh"
        try? script.write(toFile: scriptPath, atomically: true, encoding: .utf8)

        let installer = Process()
        installer.executableURL = URL(fileURLWithPath: "/bin/bash")
        installer.arguments = [scriptPath]
        try? installer.run()

        NSApp.terminate(nil)
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

        // Check for updates silently on launch
        Updater.checkForUpdate(silent: true) { release in
            if let release = release {
                Updater.promptAndUpdate(release: release)
            }
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
        menu.addItem(NSMenuItem(title: "Check for Updates...", action: #selector(checkForUpdates), keyEquivalent: "u"))
        menu.addItem(NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))

        let versionItem = NSMenuItem(title: "v\(currentVersion)", action: nil, keyEquivalent: "")
        versionItem.isEnabled = false
        menu.addItem(NSMenuItem.separator())
        menu.addItem(versionItem)
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

    @objc func checkForUpdates() {
        Updater.checkForUpdate(silent: false) { release in
            if let release = release {
                Updater.promptAndUpdate(release: release)
            }
        }
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
