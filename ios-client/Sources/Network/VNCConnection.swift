import Foundation
import Network

struct ServerInitInfo {
    let width: Int
    let height: Int
}

enum VNCError: Error, LocalizedError {
    case connectionFailed
    case handshakeFailed
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .connectionFailed: return "Failed to connect to server"
        case .handshakeFailed: return "VNC handshake failed"
        case .invalidResponse: return "Invalid server response"
        }
    }
}

class VNCConnection {
    private var connection: NWConnection?
    private var host: String = ""
    private var port: UInt16 = 5900
    private var framebufferWidth: UInt16 = 0
    private var framebufferHeight: UInt16 = 0
    private var isHandshakeCompleted = false

    var onFrameData: ((Data) -> Void)?
    var onDisconnected: (() -> Void)?

    func connect(to ip: String, port: UInt16, completion: @escaping (Result<ServerInitInfo, Error>) -> Void) {
        self.host = ip
        self.port = port
        self.isHandshakeCompleted = false

        let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(ip), port: NWEndpoint.Port(rawValue: port)!)
        let parameters = NWParameters.tcp

        connection = NWConnection(to: endpoint, using: parameters)

        connection?.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.performHandshake(completion: completion)
            case .failed(let error):
                self?.failHandshakeOnce(completion: completion, error: error)
            case .cancelled:
                self?.onDisconnected?()
            default:
                break
            }
        }

        connection?.start(queue: DispatchQueue.global(qos: .userInitiated))
    }

    func disconnect() {
        connection?.cancel()
        connection = nil
    }

    func startReceiving() {
        requestFramebufferUpdate()
    }

    private func performHandshake(completion: @escaping (Result<ServerInitInfo, Error>) -> Void) {
        receiveServerVersion(completion: completion)
    }

    private func receiveServerVersion(completion: @escaping (Result<ServerInitInfo, Error>) -> Void) {
        connection?.receive(minimumIncompleteLength: 12, maximumLength: 12) { [weak self] _, _, _, error in
            guard error == nil else {
                completion(.failure(VNCError.handshakeFailed))
                return
            }
            guard let self = self else { return }

            let clientVersion = "RFB 003.008\n"
            self.connection?.send(content: clientVersion.data(using: .ascii)!, completion: .contentProcessed { [weak self] error in
                if error != nil {
                    completion(.failure(VNCError.handshakeFailed))
                    return
                }
                self?.receiveSecurityTypes(completion: completion)
            })
        }
    }

    private func receiveSecurityTypes(completion: @escaping (Result<ServerInitInfo, Error>) -> Void) {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 1) { [weak self] data, _, _, error in
            guard let self = self, let data = data, error == nil else {
                completion(.failure(VNCError.handshakeFailed))
                return
            }

            let numTypes = Int(data[0])
            if numTypes > 0 {
                self.connection?.receive(minimumIncompleteLength: numTypes, maximumLength: numTypes) { [weak self] data, _, _, error in
                    guard let self = self, let data = data, error == nil else {
                        completion(.failure(VNCError.handshakeFailed))
                        return
                    }
                    guard data.contains(0x01) else {
                        completion(.failure(VNCError.handshakeFailed))
                        return
                    }
                    self.connection?.send(content: Data([0x01]), completion: .contentProcessed { [weak self] error in
                        if error != nil {
                            completion(.failure(VNCError.handshakeFailed))
                            return
                        }
                        self?.receiveSecurityResult(completion: completion)
                    })
                }
            } else {
                self.receiveSecurityFailureReason(completion: completion)
            }
        }
    }

    private func receiveSecurityResult(completion: @escaping (Result<ServerInitInfo, Error>) -> Void) {
        connection?.receive(minimumIncompleteLength: 4, maximumLength: 4) { [weak self] data, _, _, error in
            guard let self = self, let data = data, error == nil else {
                completion(.failure(VNCError.handshakeFailed))
                return
            }

            let result = data[3]
            if result == 0x00 {
                self.sendClientInit(completion: completion)
            } else {
                completion(.failure(VNCError.handshakeFailed))
            }
        }
    }

    private func sendClientInit(completion: @escaping (Result<ServerInitInfo, Error>) -> Void) {
        // shared-flag = 1 means the client is willing to share the server with other viewers.
        connection?.send(content: Data([0x01]), completion: .contentProcessed { [weak self] error in
            if error != nil {
                completion(.failure(VNCError.handshakeFailed))
                return
            }
            self?.receiveServerInit(completion: completion)
        })
    }

    private func receiveServerInit(completion: @escaping (Result<ServerInitInfo, Error>) -> Void) {
        receiveExact(length: 16) { [weak self] data in
            guard let self = self, let data = data else {
                completion(.failure(VNCError.handshakeFailed))
                return
            }

            let width = Int(data[0]) << 8 | Int(data[1])
            let height = Int(data[2]) << 8 | Int(data[3])
            self.framebufferWidth = UInt16(width)
            self.framebufferHeight = UInt16(height)
            let nameLength = Int(data[12]) << 24 | Int(data[13]) << 16 | Int(data[14]) << 8 | Int(data[15])

            if nameLength > 0 {
                self.receiveExact(length: nameLength) { _ in
                    let info = ServerInitInfo(width: width, height: height)
                    self.isHandshakeCompleted = true
                    completion(.success(info))
                }
            } else {
                let info = ServerInitInfo(width: width, height: height)
                self.isHandshakeCompleted = true
                completion(.success(info))
            }
        }
    }

    private func receiveSecurityFailureReason(completion: @escaping (Result<ServerInitInfo, Error>) -> Void) {
        receiveExact(length: 4) { [weak self] lengthData in
            guard let self = self, let lengthData = lengthData else {
                completion(.failure(VNCError.handshakeFailed))
                return
            }
            let reasonLength = Int(lengthData[0]) << 24 | Int(lengthData[1]) << 16 | Int(lengthData[2]) << 8 | Int(lengthData[3])
            guard reasonLength > 0 else {
                completion(.failure(VNCError.handshakeFailed))
                return
            }
            self.receiveExact(length: reasonLength) { reasonData in
                let reason = reasonData.flatMap { String(data: $0, encoding: .utf8) } ?? "Security negotiation failed"
                completion(.failure(NSError(domain: "VNCConnection", code: -2, userInfo: [NSLocalizedDescriptionKey: reason])))
            }
        }
    }

    private func failHandshakeOnce(completion: @escaping (Result<ServerInitInfo, Error>) -> Void, error: Error) {
        guard !isHandshakeCompleted else { return }
        isHandshakeCompleted = true
        completion(.failure(error))
    }

    private func receiveExact(length: Int, completion: @escaping (Data?) -> Void) {
        receiveExactHelper(remaining: length, data: Data(), completion: completion)
    }

    private func receiveExactHelper(remaining: Int, data: Data, completion: @escaping (Data?) -> Void) {
        guard remaining > 0 else {
            completion(data)
            return
        }

        connection?.receive(minimumIncompleteLength: 1, maximumLength: remaining) { [weak self] chunk, _, _, error in
            guard let self = self, let chunk = chunk, error == nil else {
                completion(nil)
                return
            }
            var newData = data
            newData.append(chunk)
            let newRemaining = max(0, remaining - chunk.count)
            self.receiveExactHelper(remaining: newRemaining, data: newData, completion: completion)
        }
    }

    func requestFramebufferUpdate() {
        var data = Data()
        data.append(0x03)
        data.append(0x01)
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x00])
        data.append(contentsOf: withUnsafeBytes(of: framebufferWidth.bigEndian) { Data($0) })
        data.append(contentsOf: withUnsafeBytes(of: framebufferHeight.bigEndian) { Data($0) })

        connection?.send(content: data, completion: .contentProcessed { [weak self] _ in
            self?.receiveMessages()
        })
    }

    private func receiveMessages() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 1) { [weak self] data, _, isComplete, error in
            if let data = data, error == nil {
                guard let self = self else { return }
                let messageType = data[0]

                switch messageType {
                case 0x00:
                    self.handleFramebufferUpdate()
                case 0x01:
                    self.handleColorMap()
                case 0x02:
                    self.handleBell()
                case 0x03:
                    self.handleServerCutText()
                default:
                    self.receiveMessages()
                }
            } else if isComplete {
                self?.onDisconnected?()
            }
        }
    }

    private func handleFramebufferUpdate() {
        receiveExact(length: 3) { [weak self] data in
            guard let self = self, let data = data else { return }

            let numRects = Int(data[1]) << 8 | Int(data[2])
            self.receiveRectangles(count: numRects)
        }
    }

    private func receiveRectangles(count: Int) {
        guard count > 0 else {
            requestFramebufferUpdate()
            return
        }

        receiveExact(length: 12) { [weak self] data in
            guard let self = self, let data = data else { return }

            let width = Int(data[4]) << 8 | Int(data[5])
            let height = Int(data[6]) << 8 | Int(data[7])
            let encoding = Int32(data[8]) << 24 | Int32(data[9]) << 16 | Int32(data[10]) << 8 | Int32(data[11])

            self.receiveRectangleData(width: width, height: height, encoding: encoding, remaining: count - 1)
        }
    }

    private func receiveRectangleData(width: Int, height: Int, encoding: Int32, remaining: Int) {
        guard encoding == 0 else {
            onDisconnected?()
            return
        }
        let length = width * height * 4

        receiveExact(length: length) { [weak self] data in
            guard let self = self, let data = data else { return }

            self.onFrameData?(data)
            self.receiveRectangles(count: remaining)
        }
    }

    private func handleColorMap() {
        receiveExact(length: 5) { [weak self] data in
            guard let self = self, let data = data else { return }

            let numColors = Int(data[3]) << 8 | Int(data[4])
            self.receiveExact(length: numColors * 6) { _ in
                self.receiveMessages()
            }
        }
    }

    private func handleBell() {
        receiveMessages()
    }

    private func handleServerCutText() {
        receiveExact(length: 7) { [weak self] data in
            guard let self = self, let data = data else { return }

            let length = Int(data[3]) << 24 | Int(data[4]) << 16 | Int(data[5]) << 8 | Int(data[6])

            self.receiveExact(length: length) { _ in
                self.receiveMessages()
            }
        }
    }

    func sendPointerEvent(x: Int, y: Int, buttonMask: UInt8) {
        var data = Data()
        data.append(0x05)
        data.append(buttonMask)
        data.append(UInt8((x >> 8) & 0xFF))
        data.append(UInt8(x & 0xFF))
        data.append(UInt8((y >> 8) & 0xFF))
        data.append(UInt8(y & 0xFF))

        connection?.send(content: data, completion: .contentProcessed { _ in })
    }

    func sendKeyEvent(key: UInt32, down: Bool) {
        var data = Data()
        data.append(0x04)
        data.append(down ? 0x01 : 0x00)
        data.append(contentsOf: [0x00, 0x00])
        data.append(UInt8((key >> 24) & 0xFF))
        data.append(UInt8((key >> 16) & 0xFF))
        data.append(UInt8((key >> 8) & 0xFF))
        data.append(UInt8(key & 0xFF))

        connection?.send(content: data, completion: .contentProcessed { _ in })
    }

    func sendText(_ text: String) {
        for char in text.unicodeScalars {
            let key = UInt32(char.value)
            sendKeyEvent(key: key, down: true)
            sendKeyEvent(key: key, down: false)
        }
    }
}
        isHandshakeCompleted = false
