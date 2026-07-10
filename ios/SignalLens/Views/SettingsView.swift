import SwiftUI

struct SettingsView: View {
    @AppStorage("backendURL") private var backendURL = "http://127.0.0.1:8000"
    @AppStorage("calibrationOffsetDb") private var calibrationOffset = 0.0

    var body: some View {
        NavigationStack {
            ZStack {
                GlassBackground()
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        
                        // Backend Section
                        GlassSectionHeader(title: "Backend")
                        GlassCard(glowColor: .blue) {
                            VStack(alignment: .leading, spacing: 10) {
                                GlassTextField(title: "URL", text: $backendURL, placeholder: "http://127.0.0.1:8000", keyboardType: .URL)
                                
                                Text("Simulator: 127.0.0.1 works. Physical iPhone: use your Mac's LAN IP (e.g. http://100.70.5.x:8000) with the backend run via uvicorn --host 0.0.0.0.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        
                        // Calibration Section
                        GlassSectionHeader(title: "Calibration")
                        GlassCard(glowColor: .orange) {
                            VStack(alignment: .leading, spacing: 16) {
                                HStack {
                                    Text("Proxy→dBm Offset")
                                        .font(.subheadline.bold())
                                    Spacer()
                                    Text(String(format: "%+.1f dB", calibrationOffset))
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                
                                Button(role: .destructive) {
                                    calibrationOffset = 0
                                } label: {
                                    Text("Reset Calibration")
                                        .font(.subheadline.bold())
                                        .foregroundStyle(.red)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 8)
                                        .background(.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(.red.opacity(0.3), lineWidth: 1)
                                        )
                                }
                                
                                Text("Offset learned from your Field Test Mode entries. Applied to the live estimated dBm readout.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        
                        // About Section
                        GlassSectionHeader(title: "About")
                        GlassCard(glowColor: .purple) {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Text("Signal Lens")
                                        .font(.subheadline.bold())
                                    Spacer()
                                    Text("0.1.0 (MVP)")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                
                                Text("Predictions are physics-model estimates (path loss + building LOS + terrain), not measurements. iOS does not expose raw dBm; the live readout is a throughput/latency proxy corrected by your calibrations.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Settings")
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }
}
