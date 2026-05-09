import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = VNCViewModel()
    @State private var ipAddress: String = ""
    @State private var showingSettings: Bool = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                if viewModel.isConnected {
                    RemoteScreenView(viewModel: viewModel)
                } else {
                    VStack(spacing: 30) {
                        Image(systemName: "desktopcomputer")
                            .font(.system(size: 80))
                            .foregroundColor(.blue)

                        Text("MacView")
                            .font(.largeTitle)
                            .fontWeight(.bold)

                        Text("Connect to your Mac remotely")
                            .foregroundColor(.secondary)

                        VStack(spacing: 16) {
                            TextField("Mac IP Address (e.g., 192.168.1.100)", text: $ipAddress)
                                .textFieldStyle(.roundedBorder)
                                .textInputAutocapitalization(.never)
                                .disableAutocorrection(true)

                            Button(action: connect) {
                                HStack {
                                    if viewModel.isConnecting {
                                        ProgressView()
                                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    }
                                    Text(viewModel.isConnecting ? "Connecting..." : "Connect")
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(10)
                            }
                            .disabled(ipAddress.isEmpty || viewModel.isConnecting)
                        }
                        .padding(.horizontal, 40)

                        // Connection status message
                        if !viewModel.statusMessage.isEmpty && viewModel.isConnecting {
                            Text(viewModel.statusMessage)
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }

                        // Error message with retry button
                        if let error = viewModel.errorMessage {
                            VStack(spacing: 12) {
                                Text(error)
                                    .foregroundColor(.red)
                                    .font(.caption)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal)

                                if !ipAddress.isEmpty {
                                    Button(action: connect) {
                                        Text("Retry")
                                            .font(.subheadline)
                                            .padding(.horizontal, 24)
                                            .padding(.vertical, 8)
                                            .background(Color.red.opacity(0.1))
                                            .foregroundColor(.red)
                                            .cornerRadius(6)
                                    }
                                }
                            }
                        }

                        Spacer()
                    }
                    .padding(.top, 60)
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if viewModel.isConnected {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Disconnect") {
                            viewModel.disconnect()
                        }
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showingSettings = true }) {
                        Image(systemName: "gear")
                    }
                }
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView(viewModel: viewModel)
            }
        }
        .onAppear {
            ipAddress = viewModel.savedIPAddress
        }
    }

    private func connect() {
        viewModel.connect(to: ipAddress)
    }
}

struct SettingsView: View {
    @ObservedObject var viewModel: VNCViewModel
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Connection") {
                    TextField("Default IP Address", text: $viewModel.savedIPAddress)
                        .textInputAutocapitalization(.never)
                }

                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}
