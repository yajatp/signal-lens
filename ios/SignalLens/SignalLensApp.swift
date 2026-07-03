import SwiftUI

@main
struct SignalLensApp: App {
    @StateObject private var locationManager = LocationManager()
    @StateObject private var proxyMonitor = SignalProxyMonitor()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(locationManager)
                .environmentObject(proxyMonitor)
        }
    }
}
