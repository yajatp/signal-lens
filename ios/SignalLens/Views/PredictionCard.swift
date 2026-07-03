import SwiftUI

/// Bottom card showing the predicted signal + the "why" breakdown.
struct PredictionCard: View {
    let prediction: Prediction
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                if let dbm = prediction.predictedDbm {
                    Text("\(Int(dbm)) dBm")
                        .font(.title2.bold())
                        .foregroundStyle(color(for: dbm))
                    Text(quality(for: dbm))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Text("No prediction available").font(.headline)
                }
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
            }

            Text(prediction.explanation)
                .font(.subheadline)

            if prediction.predictedDbm != nil {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                    GridRow {
                        Text("Baseline (path loss)")
                        Text("\(prediction.baselineDbm.map { String(format: "%.1f dBm", $0) } ?? "—")")
                    }
                    GridRow {
                        Text("Buildings (\(prediction.obstructionCount))")
                        Text("−\(String(format: "%.1f", prediction.obstructionPenaltyDb)) dB")
                    }
                    GridRow {
                        Text("Terrain")
                        Text("−\(String(format: "%.1f", prediction.terrainPenaltyDb)) dB")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            if !prediction.obstructions.isEmpty {
                DisclosureGroup("Blocking buildings") {
                    ForEach(prediction.obstructions) { o in
                        HStack {
                            Text(o.buildingType.replacingOccurrences(of: "_", with: " "))
                            Spacer()
                            Text(String(format: "%.0f m tall (%@)", o.heightM, o.heightSource))
                                .foregroundStyle(.secondary)
                        }
                        .font(.caption)
                    }
                }
                .font(.caption.bold())
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func color(for dbm: Double) -> Color {
        switch dbm {
        case (-85)...: .green
        case (-100)..<(-85): .yellow
        case (-115)..<(-100): .orange
        default: .red
        }
    }

    private func quality(for dbm: Double) -> String {
        switch dbm {
        case (-85)...: "Excellent"
        case (-100)..<(-85): "Good"
        case (-115)..<(-100): "Fair"
        default: "Poor / dead zone"
        }
    }
}
