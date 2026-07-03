import SwiftUI

/// Walk-test mode: logs predicted vs. proxy-actual along a route every 10 s.
struct WalkTestView: View {
    @EnvironmentObject private var locationManager: LocationManager
    @EnvironmentObject private var proxyMonitor: SignalProxyMonitor
    @StateObject private var recorder = WalkTestRecorder()

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                HStack(spacing: 24) {
                    stat("Samples", "\(recorder.samples.count)")
                    stat("Proxy", proxyMonitor.proxyScore.map { String(format: "%.0f", $0) } ?? "—")
                    stat("Est. dBm", proxyMonitor.estimatedDbm.map { "\(Int($0))" } ?? "—")
                }
                .padding(.top)

                Button(action: toggle) {
                    Label(
                        recorder.isRecording ? "Stop Walk Test" : "Start Walk Test",
                        systemImage: recorder.isRecording ? "stop.circle.fill" : "record.circle"
                    )
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(recorder.isRecording ? .red : .green)
                .padding(.horizontal)
                .disabled(!recorder.isRecording && locationManager.location == nil)

                if let err = recorder.lastError {
                    Text(err).font(.caption).foregroundStyle(.red)
                }

                List {
                    ForEach(recorder.samples.reversed()) { s in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(s.timestamp, style: .time).font(.caption.bold())
                                Spacer()
                                if let pred = s.predictedDbm {
                                    Text("pred \(Int(pred)) dBm").font(.caption)
                                }
                                if let proxy = s.actualProxySignal {
                                    Text("proxy \(Int(proxy))").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Text(String(format: "%.5f, %.5f · %d obstruction(s)", s.lat, s.lon, s.obstructionCount ?? 0))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .listStyle(.plain)
                .overlay {
                    if recorder.samples.isEmpty {
                        ContentUnavailableView(
                            "No samples yet",
                            systemImage: "figure.walk",
                            description: Text("Start a walk test to log predicted vs. actual signal along your route.")
                        )
                    }
                }
            }
            .navigationTitle("Walk Test")
            .toolbar {
                if !recorder.samples.isEmpty && !recorder.isRecording {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Clear") { recorder.clear() }
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
