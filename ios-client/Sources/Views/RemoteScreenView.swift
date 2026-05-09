import SwiftUI
import UIKit

struct RemoteScreenView: View {
    @ObservedObject var viewModel: VNCViewModel
    @State private var viewSize: CGSize = .zero
    @State private var isDragging = false

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                VNCFramebufferView(viewModel: viewModel)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .background(Color.black)
                    .onAppear {
                        viewSize = geometry.size
                    }
                    .onChange(of: geometry.size) { newSize in
                        viewSize = newSize
                    }
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let x = Int(value.location.x * viewModel.screenScaleX(for: viewSize.width))
                                let y = Int(value.location.y * viewModel.screenScaleY(for: viewSize.height))
                                viewModel.sendPointerEvent(x: x, y: y, buttonMask: 0x01)
                                isDragging = true
                            }
                            .onEnded { _ in
                                if isDragging {
                                    viewModel.sendPointerEvent(x: 0, y: 0, buttonMask: 0x00)
                                    isDragging = false
                                }
                            }
                    )
                    .simultaneousGesture(
                        LongPressGesture(minimumDuration: 0.5)
                            .onEnded { _ in
                                let x = Int(viewModel.lastX)
                                let y = Int(viewModel.lastY)
                                viewModel.sendPointerEvent(x: x, y: y, buttonMask: 0x02)
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                    viewModel.sendPointerEvent(x: x, y: y, buttonMask: 0x00)
                                }
                            }
                    )

                VStack {
                    Spacer()
                    KeyboardToolbar(onTextChange: { text in
                        viewModel.sendText(text)
                    })
                }
            }
        }
        .ignoresSafeArea()
    }
}

struct KeyboardToolbar: UIViewRepresentable {
    var onTextChange: (String) -> Void

    func makeUIView(context: Context) -> UITextField {
        let textField = UITextField(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
        textField.placeholder = "Type here..."
        textField.autocapitalizationType = .none
        textField.autocorrectionType = .no
        textField.returnKeyType = .done
        textField.delegate = context.coordinator
        textField.addTarget(context.coordinator, action: #selector(Coordinator.textDidChange(_:)), for: .editingChanged)
        textField.backgroundColor = .clear
        textField.alpha = 0.01
        return textField
    }

    func updateUIView(_ uiView: UITextField, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onTextChange: onTextChange)
    }

    class Coordinator: NSObject, UITextFieldDelegate {
        var onTextChange: (String) -> Void

        init(onTextChange: @escaping (String) -> Void) {
            self.onTextChange = onTextChange
        }

        @objc func textDidChange(_ textField: UITextField) {
            if let text = textField.text, !text.isEmpty {
                onTextChange(text)
                textField.text = ""
            }
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            onTextChange("\n")
            textField.text = ""
            return true
        }
    }
}

struct VNCFramebufferView: UIViewRepresentable {
    @ObservedObject var viewModel: VNCViewModel

    func makeUIView(context: Context) -> VNCImageView {
        let view = VNCImageView()
        view.contentMode = .scaleAspectFit
        view.backgroundColor = .black
        return view
    }

    func updateUIView(_ uiView: VNCImageView, context: Context) {
        if let imageData = viewModel.frameImageData {
            uiView.updateImage(data: imageData, width: viewModel.screenWidth, height: viewModel.screenHeight)
        }
    }
}

class VNCImageView: UIImageView {
    func updateImage(data: Data, width: Int, height: Int) {
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)

        guard let provider = CGDataProvider(data: data as CFData),
              let cgImage = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: bitmapInfo,
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
              ) else { return }

        DispatchQueue.main.async {
            self.image = UIImage(cgImage: cgImage)
        }
    }
}
