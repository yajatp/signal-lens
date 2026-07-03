import SwiftUI

/// Manual Field Test Mode calibration flow (spec §3.2):
/// the user reads real RSRP from iOS Field Test Mode and enters it here.
/// The entry is logged server-side as ground truth AND used locally to correct
/// the throughput→signal-quality mapping.
struct CalibrationView: View {
    @EnvironmentObject private var locationManager: LocationManager
    @EnvironmentObject private var proxyMonitor: SignalProxyMonitor

    @State private var rsrpText = ""
    @State private var submitting = false
    @State private var resultMessage: String?
    @State private var resultIsError = false

    var body: some View {
        NavigationStack {
            Form {
                Section("How to read your real signal") {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Dial *3001#12345#* and press call", systemImage: "1.circle")
                        Label("Open LTE (or 5G) → Serving Cell Meas", systemImage: "2.circle")
                        Label("Read the rsrp value (e.g. -98)", systemImage: "3.circle")
                        Label("Return here and enter it below", systemImage: "4.circle")
                    }
                    .font(.subheadline)
                }

                Section("Field Test RSRP (dBm)") {
                    TextField("-98", text: $rsrpText)
                        .keyboardType(.numbersAndPunctuation)
                    if let loc = locationManager.location {
                        Text(String(format: "Will be logged at %.5f, %.5f", loc.coordinate.latitude, loc.coordinate.longitude))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Waiting for GPS fix…")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }

                Section {
                    Button(action: submit) {
                        if submitting { ProgressView() } else { Text("Submit calibration point") }
                    }
                    .disabled(submitting || locationManager.location == nil || parsedRsrp == nil)

                    if let msg = resultMessage {
                        Text(msg)
                            .font(.caption)
                            .foregroundStyle(resultIsError ? .red : .green)
                    }
                } footer: {
                    Text("Each calibration point corrects the live proxy estimate on this device and is stored server-side as ground truth for the ML residual model.")
                }
            }
            .navigationTitle("Calibrate")
        }
    }

    private var parsedRsrp: Double? {
        guard let value = Double(rsrpText.trimmingCharacters(in: .whitespaces)), (-160...(-20)).contains(value) else {
            return nil
        }
        return value
    }

    private func submit() {
        guard let rsrp = parsedRsrp, let loc = locationManager.location else { return }
        submitting = true
        resultMessage = nil
        Task {
            defer { submitting = false }
            do {
                let out = try await APIClient.submitMeasurement(MeasurementIn(
                    lat: loc.coordinate.latitude,
                    lon: loc.coordinate.longitude,
                    actualProxySignal: proxyMonitor.proxyScore,
                    actualFieldTestDbm: rsrp,
                    source: "calibration"
                ))
                proxyMonitor.applyCalibration(fieldTestDbm: rsrp)
                let delta = out.predictedDbm.map { String(format: "%+.1f dB vs. physics prediction", rsrp - $0) } ?? ""
                resultMessage = "Saved. \(delta)"
                resultIsError = false
                rsrpText = ""
            } catch {
                resultMessage = "Failed to save: \(error.localizedDescription)"
                resultIsError = true
            }
        }
    }
}
