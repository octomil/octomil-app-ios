import SwiftUI
import AVFoundation
import Octomil

struct PairScreen: View {
    @EnvironmentObject private var appState: AppState
    @State private var showScanner = false

    var body: some View {
        NavigationStack {
            Group {
                if let code = appState.pendingPairingCode {
                    PairingScreen(
                        token: code,
                        host: appState.serverURL,
                        onTryModel: { modelInfo in
                            let (capability, streaming) = StoredModel.inferCapability(from: modelInfo.runtime)
                            let stored = StoredModel(
                                from: modelInfo,
                                capability: capability,
                                supportsStreaming: streaming
                            )
                            appState.addPairedModel(modelInfo)
                            appState.addStoredModel(stored)
                            // Auto-register device using credentials from pairing
                            if let token = modelInfo.accessToken, !token.isEmpty,
                               let org = modelInfo.orgId, !org.isEmpty {
                                appState.deviceToken = token
                                appState.orgId = org
                                appState.initializeClient()
                            }
                            appState.showPairingSheet = false
                            appState.pendingPairingCode = nil
                            appState.selectedTab = .home
                        },
                        onDismiss: {
                            appState.pendingPairingCode = nil
                        }
                    )
                    .id(code)
                } else {
                    VStack(spacing: 24) {
                        Spacer()

                        Image(systemName: "qrcode.viewfinder")
                            .font(.system(size: 64))
                            .foregroundStyle(.secondary)

                        Text("Ready to Pair")
                            .font(.title2.bold())

                        Text("Scan a QR code or run\n`octomil deploy <model> --phone`\nto pair.")
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)

                        Button {
                            showScanner = true
                        } label: {
                            Label("Scan QR Code", systemImage: "camera.fill")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                        .buttonStyle(.borderedProminent)
                        .padding(.horizontal, 40)

                        if appState.localPort > 0 {
                            Text("Listening on port \(appState.localPort)")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }

                        Spacer()
                    }
                    .padding()
                }
            }
            .navigationTitle("Pair Device")
            .sheet(isPresented: $showScanner) {
                QRScannerView { code in
                    showScanner = false
                    handleScannedCode(code)
                }
            }
        }
    }

    private func handleScannedCode(_ code: String) {
        // QR code may be a URL like octomil://pair?code=X&host=Y or just a raw code
        if let url = URL(string: code),
           let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let items = components.queryItems {
            let pairingCode = items.first(where: { $0.name == "code" || $0.name == "token" })?.value
            let host = items.first(where: { $0.name == "host" || $0.name == "server" })?.value
            if let host, !host.isEmpty {
                appState.serverURL = host
                appState.initializeClient()
            }
            if let pairingCode {
                appState.pendingPairingCode = pairingCode
            }
        } else {
            // Treat as raw pairing code
            appState.pendingPairingCode = code
        }
    }
}

// MARK: - QR Scanner

struct QRScannerView: UIViewControllerRepresentable {
    let onCodeScanned: (String) -> Void

    func makeUIViewController(context: Context) -> QRScannerViewController {
        let vc = QRScannerViewController()
        vc.onCodeScanned = onCodeScanned
        return vc
    }

    func updateUIViewController(_ uiViewController: QRScannerViewController, context: Context) {}
}

final class QRScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onCodeScanned: ((String) -> Void)?
    private var captureSession: AVCaptureSession?
    private var hasScanned = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        let session = AVCaptureSession()
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            showError("Camera not available")
            return
        }

        session.addInput(input)

        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else {
            showError("Cannot process QR codes")
            return
        }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = [.qr]

        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.frame = view.bounds
        preview.videoGravity = .resizeAspectFill
        view.layer.addSublayer(preview)

        captureSession = session

        // Add close button
        let closeButton = UIButton(type: .close)
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(closeButton)
        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            closeButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
        ])

        // Add viewfinder overlay
        let overlay = UIImageView(image: UIImage(systemName: "viewfinder"))
        overlay.tintColor = .white.withAlphaComponent(0.5)
        overlay.contentMode = .scaleAspectFit
        overlay.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(overlay)
        NSLayoutConstraint.activate([
            overlay.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            overlay.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            overlay.widthAnchor.constraint(equalToConstant: 200),
            overlay.heightAnchor.constraint(equalToConstant: 200),
        ])
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.captureSession?.startRunning()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        captureSession?.stopRunning()
    }

    @objc private func closeTapped() {
        dismiss(animated: true)
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard !hasScanned,
              let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let value = object.stringValue else { return }
        hasScanned = true
        captureSession?.stopRunning()
        onCodeScanned?(value)
    }

    private func showError(_ message: String) {
        let label = UILabel()
        label.text = message
        label.textColor = .white
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }
}
