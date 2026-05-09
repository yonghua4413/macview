import Foundation
import Network

class VNCServer {
    private var listener: NWListener?
    private var sessionHandlers: [VNCSessionHandler] = []
    private let port: UInt16
    private(set) var isRunning = false

    var onClientConnected: (() -> Void)?
    var onClientDisconnected: (() -> Void)?

    private let screenCapture = ScreenCapture()
    let inputSimulator = InputSimulator()

    init(port: UInt16) {
        self.port = port
    }

    func start() throws {
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true

        listener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: port)!)
        listener?.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.isRunning = true
                print("VNC Server listening on port \(self?.port ?? 0)")
            case .failed(let error):
                print("Listener failed: \(error)")
                self?.isRunning = false
            default:
                break
            }
        }

        listener?.newConnectionHandler = { [weak self] connection in
            self?.handleNewConnection(connection)
        }

        listener?.start(queue: DispatchQueue.global(qos: .userInitiated))
        screenCapture.startCapture()
    }

    func stop() {
        screenCapture.stopCapture()
        listener?.cancel()
        sessionHandlers.forEach { $0.close() }
        sessionHandlers.removeAll()
        listener = nil
        isRunning = false
    }

    private func handleNewConnection(_ connection: NWConnection) {
        let handler = VNCSessionHandler(connection: connection, screenCapture: screenCapture, inputSimulator: inputSimulator)
        handler.onClose = { [weak self] in
            self?.sessionHandlers.removeAll { $0 === handler }
            self?.onClientDisconnected?()
        }
        sessionHandlers.append(handler)
        onClientConnected?()
        handler.start()
    }
}
