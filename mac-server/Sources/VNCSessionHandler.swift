import Foundation
import Network

class VNCSessionHandler {
    private let connection: NWConnection
    private let screenCapture: ScreenCapture
    private let inputSimulator: InputSimulator
    private var isRunning = false
    private var handshakeStep = 0
    private var incrementalUpdates = false

    var onClose: (() -> Void)?

    init(connection: NWConnection, screenCapture: ScreenCapture, inputSimulator: InputSimulator) {
        self.connection = connection
        self.screenCapture = screenCapture
        self.inputSimulator = inputSimulator
    }

    func start() {
        isRunning = true
        handshakeStep = 0
        sendServerVersion()
    }

    func close() {
        isRunning = false
        connection.cancel()
    }

    private func sendServerVersion() {
        let version = "RFB 003.008\n"
        connection.send(content: version.data(using: .ascii)!, completion: .contentProcessed { [weak self] error in
            if error == nil {
                self?.receiveClientVersion()
            }
        })
    }

    private func receiveClientVersion() {
        connection.receive(minimumIncompleteLength: 12, maximumLength: 12) { [weak self] data, _, _, error in
            guard let self = self, let data = data, error == nil else {
                self?.onClose?()
                return
            }
            self.handshakeStep = 1
            self.sendSecurityTypes()
        }
    }

    private func sendSecurityTypes() {
        let securityData = Data([0x01, 0x01])
        connection.send(content: securityData, completion: .contentProcessed { [weak self] error in
            if error == nil {
                self?.receiveSecuritySelection()
            }
        })
    }

    private func receiveSecuritySelection() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1) { [weak self] data, _, _, error in
            guard let self = self, let data = data, error == nil else {
                self?.onClose?()
                return
            }
            self.sendSecurityResult()
        }
    }

    private func sendSecurityResult() {
        let result = Data([0x00, 0x00, 0x00, 0x00])
        connection.send(content: result, completion: .contentProcessed { [weak self] error in
            if error == nil {
                self?.sendServerInit()
            }
        })
    }

    private func sendServerInit() {
        guard let screenData = screenCapture.getScreenInfo() else {
            onClose?()
            return
        }

        var data = Data()
        data.append(contentsOf: withUnsafeBytes(of: UInt16(screenData.width).bigEndian) { Data($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt16(screenData.height).bigEndian) { Data($0) })

        // Pixel format: 16 bytes (RFB spec)
        data.append(0x20)              // bits-per-pixel (32)
        data.append(0x18)              // depth (24)
        data.append(0x00)              // big-endian-flag (false)
        data.append(0x01)              // true-colour-flag (true)
        data.append(0x00)              // red-max (high byte)
        data.append(0xFF)              // red-max (low byte)
        data.append(0x00)              // green-max (high byte)
        data.append(0xFF)              // green-max (low byte)
        data.append(0x00)              // blue-max (high byte)
        data.append(0xFF)              // blue-max (low byte)
        data.append(0x10)              // red-shift (16)
        data.append(0x08)              // green-shift (8)
        data.append(0x00)              // blue-shift (0)
        data.append(0x00)              // padding
        data.append(0x00)              // padding
        data.append(0x00)              // padding

        let name = "MacView VNC Server"
        data.append(contentsOf: withUnsafeBytes(of: UInt32(name.utf8.count).bigEndian) { Data($0) })
        data.append(name.data(using: .ascii) ?? Data())

        connection.send(content: data, completion: .contentProcessed { [weak self] error in
            if error == nil {
                self?.startClientMessageLoop()
            }
        })
    }

    private func startClientMessageLoop() {
        receiveClientMessage()
    }

    private func receiveClientMessage() {
        guard isRunning else { return }

        connection.receive(minimumIncompleteLength: 1, maximumLength: 1) { [weak self] data, _, isComplete, error in
            if let data = data, error == nil {
                guard let self = self else { return }
                let messageType = data[0]

                switch messageType {
                case 0x00:
                    self.handleSetPixelFormat()
                case 0x02:
                    self.handleSetEncodings()
                case 0x03:
                    self.handleFramebufferUpdateRequest()
                case 0x04:
                    self.handleKeyEvent()
                case 0x05:
                    self.handlePointerEvent()
                case 0x06:
                    self.handleClientCutText()
                default:
                    self.receiveClientMessage()
                }
            } else if isComplete {
                self?.onClose?()
            }
        }
    }

    private func handleSetPixelFormat() {
        connection.receive(minimumIncompleteLength: 19, maximumLength: 19) { [weak self] _, _, _, error in
            if error == nil {
                self?.receiveClientMessage()
            }
        }
    }

    private func handleSetEncodings() {
        connection.receive(minimumIncompleteLength: 3, maximumLength: 3) { [weak self] data, _, _, error in
            guard let self = self, let data = data, error == nil else {
                self?.receiveClientMessage()
                return
            }

            let count = Int(data[1]) << 8 | Int(data[2])
            let encodingLength = count * 4

            if encodingLength > 0 {
                self.connection.receive(minimumIncompleteLength: encodingLength, maximumLength: encodingLength) { [weak self] encodingData, _, _, error in
                    if let encodingData = encodingData, error == nil {
                        for i in 0..<count {
                            let offset = i * 4
                            let encoding = Int32(encodingData[offset]) << 24 |
                                          Int32(encodingData[offset + 1]) << 16 |
                                          Int32(encodingData[offset + 2]) << 8 |
                                          Int32(encodingData[offset + 3])
                            if encoding == 5 {
                                self?.incrementalUpdates = true
                            }
                        }
                    }
                    self?.receiveClientMessage()
                }
            } else {
                self.receiveClientMessage()
            }
        }
    }

    private func handleFramebufferUpdateRequest() {
        connection.receive(minimumIncompleteLength: 9, maximumLength: 9) { [weak self] data, _, _, error in
            guard let self = self, let data = data, error == nil else {
                self?.receiveClientMessage()
                return
            }

            self.incrementalUpdates = data[0] != 0
            self.sendFramebufferUpdate()
        }
    }

    private func sendFramebufferUpdate() {
        guard let frame = screenCapture.captureFrame() else {
            receiveClientMessage()
            return
        }
        guard let screenInfo = screenCapture.getScreenInfo() else {
            receiveClientMessage()
            return
        }

        var data = Data()
        data.append(0x00)
        data.append(0x00)
        data.append(contentsOf: withUnsafeBytes(of: UInt16(1).bigEndian) { Data($0) })

        data.append(contentsOf: withUnsafeBytes(of: UInt16(0).bigEndian) { Data($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt16(0).bigEndian) { Data($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt16(screenInfo.width).bigEndian) { Data($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt16(screenInfo.height).bigEndian) { Data($0) })

        data.append(contentsOf: withUnsafeBytes(of: UInt32(0).bigEndian) { Data($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt32(frame.count).bigEndian) { Data($0) })
        data.append(frame)

        connection.send(content: data, completion: .contentProcessed { [weak self] error in
            if error == nil {
                self?.receiveClientMessage()
            }
        })
    }

    private func handleKeyEvent() {
        receiveHandler(minLength: 7) { [weak self] data in
            guard let self = self else { return }
            let down = data[0] != 0
            let key = UInt32(data[3]) << 24 | UInt32(data[4]) << 16 | UInt32(data[5]) << 8 | UInt32(data[6])
            self.inputSimulator.simulateKeyEvent(key: key, down: down)
            self.receiveClientMessage()
        }
    }

    private func handlePointerEvent() {
        receiveHandler(minLength: 5) { [weak self] data in
            guard let self = self else { return }
            let buttonMask = data[0]
            let x = Int(UInt16(data[1]) << 8 | UInt16(data[2]))
            let y = Int(UInt16(data[3]) << 8 | UInt16(data[4]))
            self.inputSimulator.simulatePointerEvent(x: x, y: y, buttonMask: buttonMask)
            self.receiveClientMessage()
        }
    }

    private func receiveHandler(minLength: Int, handler: @escaping (Data) -> Void) {
        connection.receive(minimumIncompleteLength: minLength, maximumLength: minLength) { [weak self] data, _, isComplete, error in
            guard let data = data, error == nil else {
                if isComplete || error != nil {
                    self?.onClose?()
                }
                return
            }
            handler(data)
        }
    }

    private func handleClientCutText() {
        receiveHandler(minLength: 7) { [weak self] data in
            guard let self = self else { return }
            let length = Int(data[3]) << 24 | Int(data[4]) << 16 | Int(data[5]) << 8 | Int(data[6])

            if length > 0 {
                self.connection.receive(minimumIncompleteLength: length, maximumLength: length) { _, _, _, _ in
                    self.receiveClientMessage()
                }
            } else {
                self.receiveClientMessage()
            }
        }
    }
}
