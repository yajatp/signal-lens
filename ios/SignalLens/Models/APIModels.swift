import Foundation

struct Prediction: Codable, Identifiable, Equatable {
    var id: String { "\(lat),\(lon)" }
    let lat: Double
    let lon: Double
    let towerId: String?
    let towerLat: Double?
    let towerLon: Double?
    let towerDistanceM: Double?
    let baselineDbm: Double?
    let obstructionCount: Int
    let obstructionPenaltyDb: Double
    let terrainPenaltyDb: Double
    let terrainMaxIntrusionM: Double
    let predictedDbm: Double?
    let obstructions: [Obstruction]
    let explanation: String

    enum CodingKeys: String, CodingKey {
        case lat, lon, obstructions, explanation
        case towerId = "tower_id"
        case towerLat = "tower_lat"
        case towerLon = "tower_lon"
        case towerDistanceM = "tower_distance_m"
        case baselineDbm = "baseline_dbm"
        case obstructionCount = "obstruction_count"
        case obstructionPenaltyDb = "obstruction_penalty_db"
        case terrainPenaltyDb = "terrain_penalty_db"
        case terrainMaxIntrusionM = "terrain_max_intrusion_m"
        case predictedDbm = "predicted_dbm"
    }
}

struct Obstruction: Codable, Identifiable, Equatable {
    var id: Int { osmId }
    let osmId: Int
    let buildingType: String
    let heightM: Double
    let heightSource: String
    let clearanceM: Double

    enum CodingKeys: String, CodingKey {
        case osmId = "osm_id"
        case buildingType = "building_type"
        case heightM = "height_m"
        case heightSource = "height_source"
        case clearanceM = "clearance_m"
    }
}

struct Tower: Codable, Identifiable {
    let id: String
    let radio: String
    let mcc: Int
    let mnc: Int
    let lat: Double
    let lon: Double
    let rangeM: Double
    let samples: Int

    enum CodingKeys: String, CodingKey {
        case id, radio, mcc, mnc, lat, lon, samples
        case rangeM = "range_m"
    }
}

struct MeasurementIn: Codable {
    let lat: Double
    let lon: Double
    var deviceHeightEstimate: Double = 1.5
    var actualProxySignal: Double?
    var actualFieldTestDbm: Double?
    let source: String // walk_test | calibration | passive

    enum CodingKeys: String, CodingKey {
        case lat, lon, source
        case deviceHeightEstimate = "device_height_estimate"
        case actualProxySignal = "actual_proxy_signal"
        case actualFieldTestDbm = "actual_field_test_dbm"
    }
}

struct MeasurementOut: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let lat: Double
    let lon: Double
    let towerId: String?
    let towerDistanceM: Double?
    let obstructionCount: Int?
    let terrainPenalty: Double?
    let predictedDbm: Double?
    let actualProxySignal: Double?
    let actualFieldTestDbm: Double?
    let source: String

    enum CodingKeys: String, CodingKey {
        case id, timestamp, lat, lon, source
        case towerId = "tower_id"
        case towerDistanceM = "tower_distance_m"
        case obstructionCount = "obstruction_count"
        case terrainPenalty = "terrain_penalty"
        case predictedDbm = "predicted_dbm"
        case actualProxySignal = "actual_proxy_signal"
        case actualFieldTestDbm = "actual_field_test_dbm"
    }
}
