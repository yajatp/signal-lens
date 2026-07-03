import CoreLocation
import Foundation

/// Walk-test mode: continuous logging of predicted vs. proxy-actual along a route.
/// Each sample is POSTed to the backend, which computes and stores the physics
/// prediction alongside the proxy actual — one row of ML training data per sample.
@MainActor
final class WalkTestRecorder: ObservableObject {
    @Published var isRecording = false
    @Published var samples: [MeasurementOut] = []
    @Published var lastError: String?

    private var timer: Timer?

    func start(location: @escaping () -> CLLocation?, proxy: @escaping () -> Double?, interval: TimeInterval = 10) {
        guard !isRecording else { return }
        isRecording = true
        lastError = nil
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.capture(location: location(), proxy: proxy()) }
        }
        Task { await capture(location: location(), proxy: proxy()) }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        isRecording = false
    }

    func clear() {
        samples = []
    }

    private func capture(location: CLLocation?, proxy: Double?) async {
        guard isRecording, let loc = location else { return }
        do {
            let out = try await APIClient.submitMeasurement(MeasurementIn(
                lat: loc.coordinate.latitude,
                lon: loc.coordinate.longitude,
                actualProxySignal: proxy,
                actualFieldTestDbm: nil,
                source: "walk_test"
            ))
            samples.append(out)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }
}
