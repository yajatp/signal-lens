import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            MapScreen()
                .tabItem { Label("Map", systemImage: "map") }
            WalkTestView()
                .tabItem { Label("Walk Test", systemImage: "figure.walk") }
            CalibrationView()
                .tabItem { Label("Calibrate", systemImage: "dial.medium") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(LocationManager())
        .environmentObject(SignalProxyMonitor())
}
