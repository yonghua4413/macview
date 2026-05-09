import AppKit

class ServerDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var vncServer: VNCServer?
    private var connectedClients: Int = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        startVNCSever()
    }

    func applicationWillTerminate(_ notification: Notification) {
        vncServer?.stop()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.title = "MacView: Stopped"
            button.image = NSImage(systemSymbolName: "desktopcomputer", accessibilityDescription: nil)
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Mac VNC Server", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Status: Stopped", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Connected Clients: 0", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    private func startVNCSever() {
        vncServer = VNCServer(port: 5900)
        vncServer?.onClientConnected = { [weak self] in
            self?.connectedClients += 1
            self?.updateStatus()
        }
        vncServer?.onClientDisconnected = { [weak self] in
            self?.connectedClients = max(0, (self?.connectedClients ?? 1) - 1)
            self?.updateStatus()
        }

        do {
            try vncServer?.start()
            updateStatus()
        } catch {
            print("Failed to start VNC server: \(error)")
        }
    }

    private func updateStatus() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if let button = self.statusItem.button {
                let status = self.vncServer?.isRunning == true ? "Running" : "Stopped"
                button.title = "MacView: \(status)"
            }

            if let menu = self.statusItem.menu {
                menu.items[2].title = "Status: \(self.vncServer?.isRunning == true ? "Running" : "Stopped")"
                menu.items[3].title = "Connected Clients: \(self.connectedClients)"
            }
        }
    }

    @objc private func quitApp() {
        vncServer?.stop()
        NSApp.terminate(nil)
    }
}
