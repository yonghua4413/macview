import Foundation
import Combine
import Network
import UIKit

/// Controls the allowed interface orientations for the app.
/// Portrait when disconnected, landscape when connected for remote control.
class OrientationManager: ObservableObject {
    static let shared = OrientationManager()

    @Published var allowedOrientations: UIInterfaceOrientationMask = .portrait {
        didSet {
            if allowedOrientations == .landscape {
                UIDevice.current.setValue(UIInterfaceOrientation.landscapeRight.rawValue, forKey: "orientation")
            } else if allowedOrientations == .portrait {
                UIDevice.current.setValue(UIInterfaceOrientation.portrait.rawValue, forKey: "orientation")
            }
        }
    }
}

class VNCViewModel: ObservableObject {
    @Published var isConnected = false
    @Published var isConnecting = false
    @Published var errorMessage: String?
    @Published var statusMessage: String = ""
    @Published var frameImageData: Data?
    @Published var screenWidth: Int = 1920
    @Published var screenHeight: Int = 1080

    var savedIPAddress: String {
        get { UserDefaults.standard.string(forKey: "savedIPAddress") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "savedIPAddress") }
    }

    func screenScaleX(for viewWidth: CGFloat) -> CGFloat {
        guard viewWidth > 0 else { return 1.0 }
        return CGFloat(screenWidth) / viewWidth
    }

    func screenScaleY(for viewHeight: CGFloat) -> CGFloat {
        guard viewHeight > 0 else { return 1.0 }
        return CGFloat(screenHeight) / viewHeight
    }

    var lastX: Int = 0
    var lastY: Int = 0

    private var connection: VNCConnection?
    private var connectionQueue = DispatchQueue(label: "com.macview.vnc.connection")
    private var timeoutWorkItem: DispatchWorkItem?

    func connect(to ip: String) {
        disconnect()

        isConnecting = true
        isConnected = false
        errorMessage = nil
        statusMessage = "Connecting to \(ip):5900..."

        // Connection timeout: 10 seconds
        let timeout = DispatchWorkItem { [weak self] in
            guard let self = self, self.isConnecting else { return }
            self.isConnecting = false
            self.errorMessage = "Connection timed out. Please check the IP address and ensure the Mac is running."
            self.statusMessage = ""
            self.connection?.disconnect()
            self.connection = nil
        }
        timeoutWorkItem = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 10.0, execute: timeout)

        connection = VNCConnection()
        connection?.onDisconnected = { [weak self] in
            DispatchQueue.main.async {
                guard let self = self, self.isConnected else { return }
                self.isConnected = false
                self.errorMessage = "Connection lost"
                self.statusMessage = ""
                OrientationManager.shared.allowedOrientations = .portrait
            }
        }

        connection?.connect(to: ip, port: 5900) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.timeoutWorkItem?.cancel()
                self.isConnecting = false

                switch result {
                case .success(let info):
                    self.screenWidth = info.width
                    self.screenHeight = info.height
                    self.isConnected = true
                    self.errorMessage = nil
                    self.statusMessage = "Connected to \(ip)"
                    OrientationManager.shared.allowedOrientations = .landscape
                    self.startReceiving()

                case .failure(let error):
                    if self.errorMessage == nil {
                        self.errorMessage = error.localizedDescription
                        self.statusMessage = ""
                    }
                    self.connection = nil
                }
            }
        }
    }

    func disconnect() {
        timeoutWorkItem?.cancel()
        connection?.disconnect()
        connection = nil
        isConnected = false
        isConnecting = false
        frameImageData = nil
        errorMessage = nil
        statusMessage = ""
        OrientationManager.shared.allowedOrientations = .portrait
    }

    private func startReceiving() {
        connection?.onFrameData = { [weak self] data in
            DispatchQueue.main.async {
                self?.frameImageData = data
            }
        }

        connection?.startReceiving()
    }

    func sendPointerEvent(x: Int, y: Int, buttonMask: UInt8) {
        lastX = x
        lastY = y
        connection?.sendPointerEvent(x: x, y: y, buttonMask: buttonMask)
    }

    func sendKeyEvent(key: UInt32, down: Bool) {
        connection?.sendKeyEvent(key: key, down: down)
    }

    func sendText(_ text: String) {
        connection?.sendText(text)
    }
}
