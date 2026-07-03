import Foundation
import Network

/// The iOS workaround for "no raw dBm API" (spec §3.2):
/// NWPathMonitor for connection state + periodic latency/throughput probes as a
/// live signal-quality proxy, locally corrected by Field Test Mode calibration entries.
@MainActor
final class SignalProxyMonitor: ObservableObject {
    @Published var interfaceDescription = "unknown"
    @Published var isConnected = false
    @Published var latencyMs: Double?
    @Published var throughputMbps: Double?
    @Published var proxyScore: Double?      // 0–100 quality score
    @Published var estimatedDbm: Double?    // heuristic dBm estimate incl. calibration offset
    @Published var probing = false

    private let monitor = NWPathMonitor()
    private var timer: Timer?

    /// Rolling calibration offset (dB), updated whenever the user enters a Field Test value.
    private var calibrationOffset: Double {
        get { UserDefaults.standard.double(forKey: "calibrationOffsetDb") }
        set { UserDefaults.standard.set(newValue, forKey: "calibrationOffsetDb") }
    }

    private static let latencyURL = URL(string: "https://www.gstatic.com/generate_204")!
    private static let throughputURL = URL(string: "https://speed.cloudflare.com/__down?bytes=262144")!

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                guard let self else { return }
                self.isConnected = path.status == .satisfied
                if path.usesInterfaceType(.cellular) {
                    self.interfaceDescription = "Cellular"
                } else if path.usesInterfaceType(.wifi) {
                    self.interfaceDescription = "Wi-Fi"
                } else if path.status == .satisfied {
                    self.interfaceDescription = "Other"
                } else {
                    self.interfaceDescription = "Offline"
                }
            }
        }
        monitor.start(queue: DispatchQueue(label: "signal-lens.path-monitor"))
        start()
    }

    func start(interval: TimeInterval = 15) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.probe() }
        }
        Task { await probe() }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func probe() async {
        guard isConnected, !probing else { return }
        probing = true
        defer { probing = false }

        // Latency: round-trip time of a tiny request
        var latency: Double?
        let t0 = Date()
        if let (_, resp) = try? await URLSession.shared.data(from: Self.latencyURL),
           (resp as? HTTPURLResponse)?.statusCode ?? 0 < 400 {
            latency = Date().timeIntervalSince(t0) * 1000
        }

        // Throughput: timed 256 KB download
        var throughput: Double?
        let t1 = Date()
        if let (data, _) = try? await URLSession.shared.data(from: Self.throughputURL) {
            let seconds = Date().timeIntervalSince(t1)
            if seconds > 0 {
                throughput = Double(data.count) * 8 / seconds / 1_000_000
            }
        }

        latencyMs = latency
        throughputMbps = throughput
        recompute()
    }

    /// Called from the calibration flow: nudge the proxy→dBm mapping toward ground truth.
    func applyCalibration(fieldTestDbm: Double) {
        guard let estimate = uncalibratedDbm() else {
            calibrationOffset = 0
            return
        }
        let residual = fieldTestDbm - estimate
        // Exponential smoothing so one noisy entry doesn't swing the mapping
        calibrationOffset = calibrationOffset * 0.7 + residual * 0.3
        recompute()
    }

    private func recompute() {
        proxyScore = Self.score(latencyMs: latencyMs, throughputMbps: throughputMbps)
        if let base = uncalibratedDbm() {
            estimatedDbm = base + calibrationOffset
        } else {
            estimatedDbm = nil
        }
    }

    private func uncalibratedDbm() -> Double? {
        guard let score = Self.score(latencyMs: latencyMs, throughputMbps: throughputMbps) else { return nil }
        // Documented heuristic: linear map of quality score onto the usable RSRP range.
        // score 0 → -125 dBm (unusable), score 100 → -75 dBm (excellent).
        return -125 + (score / 100) * 50
    }

    /// 0–100 quality score from latency + throughput. Heuristic, calibration-corrected later.
    static func score(latencyMs: Double?, throughputMbps: Double?) -> Double? {
        guard latencyMs != nil || throughputMbps != nil else { return nil }
        var parts: [Double] = []
        if let lat = latencyMs {
            // 20 ms → ~100, 500 ms → ~0
            parts.append(max(0, min(100, (500 - lat) / 4.8)))
        }
        if let tp = throughputMbps {
            // 0 Mbps → 0, 50+ Mbps → 100
            parts.append(max(0, min(100, tp * 2)))
        }
        return parts.reduce(0, +) / Double(parts.count)
    }
}
