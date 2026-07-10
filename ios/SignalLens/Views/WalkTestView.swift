import SwiftUI

/// Walk-test mode: logs predicted vs. proxy-actual along a route every 10 s.
struct WalkTestView: View {
    @EnvironmentObject private var locationManager: LocationManager
    @EnvironmentObject private var proxyMonitor: SignalProxyMonitor
    @StateObject private var recorder = WalkTestRecorder()

    var body: some View {
        NavigationStack {
            ZStack {
                GlassBackground()
                
                VStack(spacing: 16) {
                    HStack(spacing: 16) {
                        GlassCard(glowColor: .indigo) {
                            stat("Samples", "\(recorder.samples.count)")
                        }
                        GlassCard(glowColor: .blue) {
                            stat("Proxy", proxyMonitor.proxyScore.map { String(format: "%.0f", $0) } ?? "—")
                        }
                        GlassCard(glowColor: .purple) {
                            stat("Est. dBm", proxyMonitor.estimatedDbm.map { "\(Int($0))" } ?? "—")
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top)

                    Button(action: toggle) {
                        Label(
                            recorder.isRecording ? "Stop Walk Test" : "Start Walk Test",
                            systemImage: recorder.isRecording ? "stop.circle.fill" : "record.circle"
                        )
                        .font(.headline)
                    }
                    .buttonStyle(GlassButtonStyle(color: recorder.isRecording ? .red : .green))
                    .padding(.horizontal)
                    .disabled(!recorder.isRecording && locationManager.location == nil)

                    if let err = recorder.lastError {
                        Text(err)
                            .font(.caption.bold())
                            .foregroundStyle(.red)
                            .padding(.horizontal)
                    }

                    if recorder.samples.isEmpty {
                        Spacer()
                        VStack(spacing: 12) {
                            Image(systemName: "figure.walk.circle")
                                .font(.system(size: 60))
                                .foregroundStyle(.secondary)
                            Text("No samples yet")
                                .font(.headline)
                            Text("Start a walk test to log predicted vs. actual signal along your route.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 40)
                        }
                        Spacer()
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 12) {
                                ForEach(recorder.samples.reversed()) { s in
                                    VStack(alignment: .leading, spacing: 6) {
                                        HStack {
                                            Image(systemName: "checkmark.circle.fill")
                                                .font(.caption)
                                                .foregroundStyle(.green)
                                            Text(s.timestamp, style: .time)
                                                .font(.caption.bold())
                                                .foregroundStyle(.white)
                                            Spacer()
                                            if let pred = s.predictedDbm {
                                                Text("Pred: \(Int(pred)) dBm")
                                                    .font(.caption.bold())
                                                    .foregroundStyle(.cyan)
                                            }
                                            if let proxy = s.actualProxySignal {
                                                Text("Proxy: \(Int(proxy))")
                                                    .font(.caption.bold())
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                        Text(String(format: "%.5f, %.5f · %d obstruction(s)", s.lat, s.lon, s.obstructionCount ?? 0))
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding()
                                    .liquidGlass(cornerRadius: 12, glowColor: .blue.opacity(0.5))
                                }
                            }
                            .padding(.horizontal)
                            .padding(.bottom, 20)
                        }
                    }
                }
            }
            .navigationTitle("Walk Test")
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                if !recorder.samples.isEmpty && !recorder.isRecording {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Clear") { recorder.clear() }
                            .font(.subheadline.bold())
                    }
                }
            }
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack {
            Text(value).font(.title3.bold())
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func toggle() {
        if recorder.isRecording {
            recorder.stop()
        } else {
            recorder.start(
                location: { [weak locationManager] in locationManager?.location },
                proxy: { [weak proxyMonitor] in proxyMonitor?.proxyScore }
            )
        }
    }
}
