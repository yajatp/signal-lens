import MapKit
import SwiftUI

/// Map view: user location + nearby towers, tap-to-predict with obstruction breakdown.
struct MapScreen: View {
    @EnvironmentObject private var locationManager: LocationManager
    @EnvironmentObject private var proxyMonitor: SignalProxyMonitor

    @State private var position: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var towers: [Tower] = []
    @State private var prediction: Prediction?
    @State private var tappedPoint: CLLocationCoordinate2D?
    @State private var loading = false
    @State private var errorMessage: String?
    @State private var visibleCenter: CLLocationCoordinate2D?
    @State private var isTrackingUser = true
    @State private var hasInitialAutoPredicted = false

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                mapView
                    .ignoresSafeArea(edges: .bottom)

                locateMeButton

                VStack(spacing: 12) {
                    LiveProxyBadge()
                        .transition(.move(edge: .top).combined(with: .opacity))
                    
                    if loading {
                        ProgressView()
                            .padding(10)
                            .background(.ultraThinMaterial, in: Circle())
                            .overlay(Circle().stroke(.white.opacity(0.3), lineWidth: 0.5))
                            .shadow(color: .black.opacity(0.1), radius: 5)
                    }
                    
                    if let msg = errorMessage {
                        Text(msg)
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(
                                Capsule().fill(LinearGradient(colors: [.red, .pink], startPoint: .leading, endPoint: .trailing))
                            )
                            .shadow(color: .red.opacity(0.3), radius: 8, y: 3)
                    }
                    
                    if let p = prediction {
                        PredictionCard(prediction: p) {
                            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                                prediction = nil
                                tappedPoint = nil
                            }
                        }
                        .transition(.asymmetric(
                            insertion: .move(edge: .bottom).combined(with: .opacity),
                            removal: .move(edge: .bottom).combined(with: .opacity)
                        ))
                    }
                }
                .padding()
                .animation(.spring(response: 0.55, dampingFraction: 0.75), value: prediction)
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: loading)
            }
            .navigationTitle("Signal Lens")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: loadTowers) {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .font(.subheadline.bold())
                    }
                }
            }
            .task { loadTowers() }
            .onChange(of: locationManager.location) { _, newLoc in
                guard let newLoc = newLoc else { return }
                
                if towers.isEmpty {
                    loadTowers()
                }
                
                // Auto-center and predict on first location fix
                if !hasInitialAutoPredicted {
                    hasInitialAutoPredicted = true
                    withAnimation(.spring(response: 0.65, dampingFraction: 0.8)) {
                        position = .region(MKCoordinateRegion(
                            center: newLoc.coordinate,
                            span: MKCoordinateSpan(latitudeDelta: 0.015, longitudeDelta: 0.015)
                        ))
                    }
                    predict(at: newLoc.coordinate)
                }
            }
        }
    }

    private var mapView: some View {
        MapReader { proxy in
            Map(position: $position) {
                UserAnnotation()
                ForEach(towers) { tower in
                    Annotation("\(tower.radio)", coordinate: CLLocationCoordinate2D(latitude: tower.lat, longitude: tower.lon)) {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .font(.caption)
                            .padding(6)
                            .background(
                                Circle()
                                    .fill(LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                            )
                            .foregroundStyle(.white)
                            .shadow(color: .blue.opacity(0.4), radius: 6, y: 3)
                    }
                }
                if let tapped = tappedPoint {
                    Marker("Prediction", coordinate: tapped)
                        .tint(.orange)
                }
                if let p = prediction, let tLat = p.towerLat, let tLon = p.towerLon, let tapped = tappedPoint {
                    MapPolyline(coordinates: [tapped, CLLocationCoordinate2D(latitude: tLat, longitude: tLon)])
                        .stroke(p.obstructionCount == 0 ? .green : .red, style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [6, 4]))
                }
            }
            .onTapGesture { screenPoint in
                guard let coord = proxy.convert(screenPoint, from: .local) else { return }
                predict(at: coord)
            }
            .onMapCameraChange { context in
                visibleCenter = context.region.center
                isTrackingUser = false
            }
        }
    }

    private var locateMeButton: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                Button(action: locateMe) {
                    Image(systemName: isTrackingUser ? "location.fill" : "location")
                        .font(.title3)
                        .foregroundStyle(isTrackingUser ? .white : .primary)
                        .padding(12)
                        .background(
                            Group {
                                if isTrackingUser {
                                    Circle()
                                        .fill(LinearGradient(colors: [.blue, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing))
                                } else {
                                    Circle()
                                        .fill(.ultraThinMaterial)
                                }
                            }
                        )
                        .overlay(
                            Circle()
                                .stroke(isTrackingUser ? .blue.opacity(0.5) : .white.opacity(0.3), lineWidth: 1)
                        )
                        .shadow(color: isTrackingUser ? .blue.opacity(0.3) : .black.opacity(0.15), radius: 8, y: 4)
                }
                .scaleEffect(isTrackingUser ? 1.05 : 1.0)
                .padding(.trailing, 16)
                .padding(.bottom, 8)
            }
        }
    }

    private var referenceCoordinate: CLLocationCoordinate2D? {
        visibleCenter ?? locationManager.location?.coordinate
    }

    private func locateMe() {
        withAnimation(.spring(response: 0.6, dampingFraction: 0.85)) {
            if let loc = locationManager.location {
                position = .region(MKCoordinateRegion(
                    center: loc.coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.015, longitudeDelta: 0.015)
                ))
            } else {
                position = .userLocation(fallback: .automatic)
            }
            isTrackingUser = true
        }
        loadTowers()
    }

    private func loadTowers() {
        guard let center = referenceCoordinate else { return }
        Task {
            do {
                towers = try await APIClient.towers(lat: center.latitude, lon: center.longitude)
                errorMessage = nil
            } catch {
                errorMessage = "Can't reach \(APIClient.baseURL.host ?? "backend") — check Settings tab"
            }
        }
    }

    private func predict(at coord: CLLocationCoordinate2D) {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            tappedPoint = coord
            loading = true
        }
        Task {
            defer {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    loading = false
                }
            }
            do {
                let p = try await APIClient.predict(lat: coord.latitude, lon: coord.longitude)
                withAnimation(.spring(response: 0.55, dampingFraction: 0.85)) {
                    prediction = p
                    errorMessage = nil
                }
            } catch {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    errorMessage = "Prediction failed — check backend at \(APIClient.baseURL.host ?? "?")"
                    prediction = nil
                }
            }
        }
    }
}

/// Compact live proxy-signal readout shown over the map.
struct LiveProxyBadge: View {
    @EnvironmentObject private var proxyMonitor: SignalProxyMonitor

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: proxyMonitor.isConnected ? "antenna.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right.slash")
                .foregroundStyle(proxyMonitor.isConnected ? .blue : .secondary)
            
            Text(proxyMonitor.interfaceDescription)
                .bold()
            
            if let dbm = proxyMonitor.estimatedDbm {
                Text("~\(Int(dbm)) dBm")
                    .bold()
            }
            if let lat = proxyMonitor.latencyMs {
                Text("\(Int(lat))ms")
                    .foregroundStyle(.secondary)
            }
            if let tp = proxyMonitor.throughputMbps {
                Text(String(format: "%.1fMbps", tp))
                    .foregroundStyle(.secondary)
            }
        }
        .font(.footnote)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .liquidGlass(cornerRadius: 30, glowColor: proxyMonitor.isConnected ? .blue : .gray)
    }
}
