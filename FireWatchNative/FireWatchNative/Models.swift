import Foundation

struct Incident: Codable, Identifiable {
    let id: String
    let title: String
    let description: String?
    let lat: Double
    let lon: Double
    let severity: String
    let status: String
    let location_name: String?
    let is_demo: Bool
    let created_at: String
}

struct Camera: Codable, Identifiable {
    let id: String
    let name: String
    let url: String
    let lat: Double
    let lon: Double
    let status: String?
}

struct Stats: Decodable {
    let fire_detections: Int
    let smoke_detections: Int
    let cameras_online: Int
    let high_risk_zones: Int
}
