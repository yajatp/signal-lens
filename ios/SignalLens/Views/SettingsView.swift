import SwiftUI

struct SettingsView: View {
    @AppStorage("backendURL") private var backendURL = "http://127.0.0.1:8000"
    @AppStorage("calibrationOffsetDb") private var calibrationOffset = 0.0

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("http://127.0.0.1:8000", text: $backendURL)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                } header: {
                    Text("Backend")
                } footer: {
                    Text("Simulator: 127.0.0.1 works. Physical iPhone: use your Mac's LAN IP (e.g. http://192.168.1.x:8000) with the backend run via uvicorn --host 0.0.0.0.")
                }

                Section {
                    LabeledContent("Proxy→dBm offset", value: String(format: "%+.1f dB", calibrationOffset))
                    Button("Reset calibration", role: .destructive) { calibrationOffset = 0 }
                } header: {
                    Text("Calibration")
                } footer: {
                    Text("Offset learned from your Field Test Mode entries. Applied to the live estimated dBm readout.")
                }

                Section("About") {
                    LabeledContent("Signal Lens", value: "0.1.0 (MVP)")
                    Text("Predictions are physics-model estimates (path loss + building LOS + terrain), not measurements. iOS does not expose raw dBm; the live readout is a throughput/latency proxy corrected by your calibrations.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
        }
    }
}
