import Foundation
import CoreGraphics
import AppKit
import ScreenCaptureKit

struct ScreenInfo {
    let width: Int
    let height: Int
    let bitsPerPixel: Int
}

class ScreenCapture: NSObject {
    private var displayID: CGDirectDisplayID = CGMainDisplayID()
    private var stream: SCStream?
    private var streamOutput: StreamOutput?
    private var lastFrame: Data?
    private var frameLock = NSLock()
    private var isCapturing = false

    func getScreenInfo() -> ScreenInfo? {
        let width = CGDisplayPixelsWide(displayID)
        let height = CGDisplayPixelsHigh(displayID)
        return ScreenInfo(width: width, height: height, bitsPerPixel: 32)
    }

    func captureFrame() -> Data? {
        frameLock.lock()
        defer { frameLock.unlock() }
        return lastFrame
    }

    func startCapture() {
        guard !isCapturing else { return }
        isCapturing = true

        Task {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                guard let display = content.displays.first(where: { $0.displayID == self.displayID }) ?? content.displays.first else {
                    self.isCapturing = false
                    return
                }

                let filter = SCContentFilter(display: display, excludingWindows: [])
                let config = SCStreamConfiguration()
                config.width = Int(CGDisplayPixelsWide(displayID))
                config.height = Int(CGDisplayPixelsHigh(displayID))
                config.pixelFormat = kCVPixelFormatType_32BGRA
                config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
                config.queueDepth = 3
                config.showsCursor = false

                streamOutput = StreamOutput(frameHandler: { [weak self] data in
                    self?.frameLock.lock()
                    self?.lastFrame = data
                    self?.frameLock.unlock()
                })

                stream = SCStream(filter: filter, configuration: config, delegate: self)

                try stream?.addStreamOutput(streamOutput!, type: .screen, sampleHandlerQueue: DispatchQueue.global(qos: .userInitiated))
                try await stream?.startCapture()
            } catch {
                print("Screen capture error: \(error)")
                self.isCapturing = false
            }
        }
    }

    func stopCapture() {
        isCapturing = false
        Task {
            try? await stream?.stopCapture()
            stream = nil
            streamOutput = nil
        }
    }
}

extension ScreenCapture: SCStreamDelegate {
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        print("Stream stopped with error: \(error)")
        isCapturing = false
    }
}

class StreamOutput: NSObject, SCStreamOutput {
    let frameHandler: (Data) -> Void

    init(frameHandler: @escaping (Data) -> Void) {
        self.frameHandler = frameHandler
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen else { return }
        guard let imageBuffer = sampleBuffer.imageBuffer else { return }

        CVPixelBufferLockBaseAddress(imageBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(imageBuffer, .readOnly) }

        let width = CVPixelBufferGetWidth(imageBuffer)
        let height = CVPixelBufferGetHeight(imageBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(imageBuffer)
        let baseAddress = CVPixelBufferGetBaseAddress(imageBuffer)

        guard let baseAddr = baseAddress else { return }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let data = Data(bytesNoCopy: baseAddr, count: height * bytesPerRow, deallocator: .none)
        guard let provider = CGDataProvider(data: data as CFData),
              let cgImage = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
              ) else { return }

        let pixelBufferSize = width * height * 4
        guard let rgbBuffer = malloc(pixelBufferSize) else { return }
        bzero(rgbBuffer, pixelBufferSize)
        defer { free(rgbBuffer) }

        guard let context = CGContext(
            data: rgbBuffer,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        frameHandler(Data(bytes: rgbBuffer, count: pixelBufferSize))
    }
}

class InputSimulator {
    private var lastButtonMask: UInt8 = 0
    private var lastPosition: CGPoint = .zero

    func simulateKeyEvent(key: UInt32, down: Bool) {
        let source = CGEventSource(stateID: .hidSystemState)
        let keyCode = CGKeyCode(key & 0xFFFF)

        if let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: down) {
            event.post(tap: .cghidEventTap)
        }
    }

    func simulatePointerEvent(x: Int, y: Int, buttonMask: UInt8) {
        let position = CGPoint(x: CGFloat(x), y: CGFloat(y))
        let buttonChanged = buttonMask != lastButtonMask
        let positionChanged = position != lastPosition

        if buttonChanged || positionChanged {
            let eventType: CGEventType
            if buttonMask & 0x01 != 0 {
                eventType = .leftMouseDown
            } else if lastButtonMask & 0x01 != 0 {
                eventType = .leftMouseUp
            } else if buttonMask & 0x02 != 0 {
                eventType = .rightMouseDown
            } else if lastButtonMask & 0x02 != 0 {
                eventType = .rightMouseUp
            } else if buttonMask & 0x04 != 0 {
                eventType = .otherMouseDown
            } else if lastButtonMask & 0x04 != 0 {
                eventType = .otherMouseUp
            } else {
                eventType = .mouseMoved
            }

            if let event = CGEvent(mouseEventSource: nil, mouseType: eventType, mouseCursorPosition: position, mouseButton: .left) {
                if buttonMask & 0x02 != 0 {
                    event.type = .rightMouseDown
                } else if lastButtonMask & 0x02 != 0 && buttonMask & 0x02 == 0 {
                    event.type = .rightMouseUp
                } else if buttonMask & 0x04 != 0 {
                    event.type = .otherMouseDown
                    event.setIntegerValueField(.mouseEventWindowUnderMousePointer, value: 2)
                } else if lastButtonMask & 0x04 != 0 && buttonMask & 0x04 == 0 {
                    event.type = .otherMouseUp
                    event.setIntegerValueField(.mouseEventWindowUnderMousePointer, value: 2)
                }
                event.post(tap: .cghidEventTap)
            }
        }

        lastButtonMask = buttonMask
        lastPosition = position
    }

    func simulateTextInput(text: String) {
        let source = CGEventSource(stateID: .hidSystemState)

        for char in text.unicodeScalars {
            if let eventDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true) {
                eventDown.keyboardSetUnicodeString(stringLength: 1, unicodeString: [UniChar(char.value)])
                eventDown.post(tap: .cghidEventTap)
            }
            if let eventUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) {
                eventUp.keyboardSetUnicodeString(stringLength: 1, unicodeString: [UniChar(char.value)])
                eventUp.post(tap: .cghidEventTap)
            }
        }
    }
}
