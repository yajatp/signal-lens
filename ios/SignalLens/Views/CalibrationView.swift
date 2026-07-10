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
            ZStack {
                GlassBackground()
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        
                        // How to use Section
                        GlassSectionHeader(title: "Instructions")
                        GlassCard(glowColor: .indigo) {
                            VStack(alignment: .leading, spacing: 12) {
                                Label("Dial *3001#12345#* and press call", systemImage: "phone.fill.connection")
                                Label("Open LTE (or 5G) → Serving Cell Meas", systemImage: "list.bullet.rectangle.portrait")
                                Label("Read the RSRP value (e.g. -98)", systemImage: "eye.fill")
                                Label("Return here and enter it below", systemImage: "square.and.pencil")
                            }
                            .font(.subheadline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        
                        // Input Section
                        GlassSectionHeader(title: "Field Test RSRP (dBm)")
                        GlassCard(glowColor: .purple) {
                            VStack(alignment: .leading, spacing: 14) {
                                HStack {
                                    Image(systemName: "hand.tap.fill")
                                        .foregroundStyle(.purple)
                                    TextField("-98", text: $rsrpText)
                                        .keyboardType(.numbersAndPunctuation)
                                        .font(.title3.bold())
                                        .foregroundStyle(.white)
                                }
                                .padding(12)
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(.white.opacity(0.15), lineWidth: 1)
                                )
                                
                                if let loc = locationManager.location {
                                    Text(String(format: "Location: %.5f, %.5f", loc.coordinate.latitude, loc.coordinate.longitude))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                } else {
                                    HStack {
                                        ProgressView().scaleEffect(0.8)
                                        Text("Waiting for GPS fix…")
                                            .font(.caption)
                                            .foregroundStyle(.orange)
                                    }
                                }
                            }
                        }
                        
                        // Action Section
                        Button(action: submit) {
                            HStack {
                                if submitting {
                                    ProgressView().tint(.white)
                                } else {
                                    Text("Submit Calibration Point")
                                }
                            }
                        }
                        .buttonStyle(GlassButtonStyle(color: .purple))
                        .disabled(submitting || locationManager.location == nil || parsedRsrp == nil)
                        
                        if let msg = resultMessage {
                            GlassCard(glowColor: resultIsError ? .red : .green) {
                                Text(msg)
                                    .font(.subheadline.bold())
                                    .foregroundStyle(resultIsError ? .red : .green)
                                    .frame(maxWidth: .infinity, alignment: .center)
                            }
                            .transition(.scale.combined(with: .opacity))
                        }
                        
                        Text("Each calibration point corrects the live proxy estimate on this device and is stored server-side as ground truth for the ML residual model.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 16)
                            .padding(.top, 10)
                    }
                    .padding()
                }
            }
            .navigationTitle("Calibrate")
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
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
