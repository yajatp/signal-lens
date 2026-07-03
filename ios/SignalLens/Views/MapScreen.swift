import MapKit
import SwiftUI

/// Map view: user location + nearby towers, tap-to-predict with obstruction breakdown.
struct MapScreen: View {
    @EnvironmentObject private var locationManager: LocationManager
    @EnvironmentObject private var proxyMonitor: SignalProxyMonitor

    @State private var position: MapCameraPosition = .userLocation(
        fallback: .region(MKCoordinateRegion(
            // Allen, TX — the MVP test region
            center: CLLocationCoordinate2D(latitude: 33.1032, longitude: -96.6706),
            span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)
        ))
    )
    @State private var towers: [Tower] = []
    @State private var prediction: Prediction?
    @State private var tappedPoint: CLLocationCoordinate2D?
    @State private var loading = false
    @State private var errorMessage: String?
    @State private var visibleCenter: CLLocationCoordinate2D?

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                MapReader { proxy in
                    Map(position: $position) {
                        UserAnnotation()
                        ForEach(towers) { tower in
                            Annotation("\(tower.radio)", coordinate: CLLocationCoordinate2D(latitude: tower.lat, longitude: tower.lon)) {
                                Image(systemName: "antenna.radiowaves.left.and.right")
                                    .font(.caption)
                                    .padding(5)
                                    .background(.blue.opacity(0.85), in: Circle())
                                    .foregroundStyle(.white)
                            }
                        }
                        if let tapped = tappedPoint {
                            Marker("Prediction", coordinate: tapped)
                                .tint(.orange)
                        }
                        if let p = prediction, let tLat = p.towerLat, let tLon = p.towerLon, let tapped = tappedPoint {
                            MapPolyline(coordinates: [tapped, CLLocationCoordinate2D(latitude: tLat, longitude: tLon)])
                                .stroke(p.obstructionCount == 0 ? .green : .red, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                        }
                    }
                    .onTapGesture { screenPoint in
                        guard let coord = proxy.convert(screenPoint, from: .local) else { return }
                        predict(at: coord)
                    }
                    .onMapCameraChange { context in
                        visibleCenter = context.region.center
                    }
                }
                .ignoresSafeArea(edges: .bottom)

                VStack(spacing: 8) {
                    LiveProxyBadge()
                    if loading { ProgressView().padding(8) }
                    if let msg = errorMessage {
                        Text(msg)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .padding(8)
                            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
                    }
                    if let p = prediction {
                        PredictionCard(prediction: p) { prediction = nil; tappedPoint = nil }
                    }
                }
                .padding()
            }
            .navigationTitle("Signal Lens")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Load Towers", systemImage: "antenna.radiowaves.left.and.right") {
                        loadTowers()
                    }
                }
            }
            .task { loadTowers() }
        }
    }

    private var referenceCoordinate: CLLocationCoordinate2D {
        visibleCenter
            ?? locationManager.location?.coordinate
            ?? CLLocationCoordinate2D(latitude: 33.1032, longitude: -96.6706)
    }

    private func loadTowers() {
        let center = referenceCoordinate
        Task {
            do {
                towers = try await APIClient.towers(lat: center.latitude, lon: center.longitude)
                errorMessage = nil
            } catch {
                errorMessage = "Couldn't load towers — is the backend running?"
            }
        }
    }

    private func predict(at coord: CLLocationCoordinate2D) {
        tappedPoint = coord
        loading = true
        Task {
            defer { loading = false }
            do {
                prediction = try await APIClient.predict(lat: coord.latitude, lon: coord.longitude)
                errorMessage = nil
            } catch {
                errorMessage = "Prediction failed — is the backend running?"
                prediction = nil
            }
        }
    }
}

/// Compact live proxy-signal readout shown over the map.
struct LiveProxyBadge: View {
    @EnvironmentObject private var proxyMonitor: SignalProxyMonitor

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: proxyMonitor.isConnected ? "wifi" : "wifi.slash")
            Text(proxyMonitor.interfaceDescription)
            if let dbm = proxyMonitor.estimatedDbm {
                Text("~\(Int(dbm)) dBm est.").bold()
            }
            if let lat = proxyMonitor.latencyMs {
                Text("\(Int(lat)) ms").foregroundStyle(.secondary)
            }
            if let tp = proxyMonitor.throughputMbps {
                Text(String(format: "%.1f Mbps", tp)).foregroundStyle(.secondary)
            }
        }
        .font(.caption)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.thinMaterial, in: Capsule())
    }
}
