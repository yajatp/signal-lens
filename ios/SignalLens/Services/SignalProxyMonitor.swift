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

    private let monitor = NWPathMonitor(requiredInterfaceType: .cellular)
    private var timer: Timer?

    /// Rolling calibration offset (dB), updated whenever the user enters a Field Test value.
    private var calibrationOffset: Double {
        get { UserDefaults.standard.double(forKey: "calibrationOffsetDb") }
        set { UserDefaults.standard.set(newValue, forKey: "calibrationOffsetDb") }
    }

    private static let latencyURL = URL(string: "https://www.gstatic.com/generate_204")!
    private static let throughputURL = URL(string: "https://speed.cloudflare.com/__down?bytes=262144")!

    init() {
        // Only care about the cellular path status now
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                guard let self else { return }
                self.isConnected = path.status == .satisfied
                self.interfaceDescription = self.isConnected ? "Cellular" : "Offline"
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

        // Use low-level NWConnection to force traffic over the cellular interface
        let latency = await performCellularLatencyPing()
        let throughput = await performCellularThroughputTest()

        latencyMs = latency
        throughputMbps = throughput
        recompute()
    }

    // MARK: - Forced Cellular Probes

    private final class Resolver<T>: @unchecked Sendable {
        private var continuation: CheckedContinuation<T, Never>?
        private let lock = NSLock()
        init(_ continuation: CheckedContinuation<T, Never>) {
            self.continuation = continuation
        }
        func resume(returning value: T) {
            lock.lock()
            defer { lock.unlock() }
            continuation?.resume(returning: value)
            continuation = nil
        }
    }

    private final class ThroughputState: @unchecked Sendable {
        private let lock = NSLock()
        private var _bytesReceived = 0
        var bytesReceived: Int {
            lock.lock()
            defer { lock.unlock() }
            return _bytesReceived
        }
        func add(_ count: Int) {
            lock.lock()
            defer { lock.unlock() }
            _bytesReceived += count
        }
    }

    /// Measures latency by timing a TLS handshake over the cellular radio.
    private func performCellularLatencyPing() async -> Double? {
        let params = NWParameters.tls
        params.requiredInterfaceType = .cellular
        let connection = NWConnection(host: "www.gstatic.com", port: .https, using: params)
        
        return await withCheckedContinuation { continuation in
            let resolver = Resolver(continuation)
            let t0 = Date()
            
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    connection.cancel()
                    resolver.resume(returning: Date().timeIntervalSince(t0) * 1000)
                case .failed(_), .cancelled:
                    resolver.resume(returning: nil)
                default:
                    break
                }
            }
            connection.start(queue: DispatchQueue.global())
            
            // 3-second timeout
            Task {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                connection.cancel()
                resolver.resume(returning: nil)
            }
        }
    }

    /// Measures throughput by downloading a 256KB payload exclusively over the cellular radio.
    private func performCellularThroughputTest() async -> Double? {
        let params = NWParameters.tls
        params.requiredInterfaceType = .cellular
        let connection = NWConnection(host: "speed.cloudflare.com", port: .https, using: params)
        
        return await withCheckedContinuation { continuation in
            let resolver = Resolver(continuation)
            let stateObj = ThroughputState()
            let t1 = Date()
            
            @Sendable func finish() {
                connection.cancel()
                let seconds = Date().timeIntervalSince(t1)
                let bytes = stateObj.bytesReceived
                if seconds > 0 && bytes > 0 {
                    let mbps = (Double(bytes) * 8) / seconds / 1_000_000
                    resolver.resume(returning: mbps)
                } else {
                    resolver.resume(returning: nil)
                }
            }
            
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    let request = "GET /__down?bytes=262144 HTTP/1.1\r\nHost: speed.cloudflare.com\r\nConnection: close\r\n\r\n".data(using: .utf8)!
                    connection.send(content: request, completion: .contentProcessed({ error in
                        if error != nil { finish() }
                    }))
                    
                    func receiveNext() {
                        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, isComplete, error in
                            if let d = data { stateObj.add(d.count) }
                            if isComplete || error != nil {
                                finish()
                            } else {
                                receiveNext()
                            }
                        }
                    }
                    receiveNext()
                    
                case .failed(_), .cancelled:
                    finish()
                default:
                    break
                }
            }
            connection.start(queue: DispatchQueue.global())
            
            // 10-second timeout
            Task {
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                finish()
            }
        }
    }

    // MARK: - Calibration & Scoring

    func applyCalibration(fieldTestDbm: Double) {
        guard let estimate = uncalibratedDbm() else {
            calibrationOffset = 0
            return
        }
        let residual = fieldTestDbm - estimate
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
        return -125 + (score / 100) * 50
    }

    static func score(latencyMs: Double?, throughputMbps: Double?) -> Double? {
        guard latencyMs != nil || throughputMbps != nil else { return nil }
        var parts: [Double] = []
        if let lat = latencyMs {
            parts.append(max(0, min(100, (500 - lat) / 4.8)))
        }
        if let tp = throughputMbps {
            parts.append(max(0, min(100, tp * 2)))
        }
        return parts.reduce(0, +) / Double(parts.count)
    }
}
