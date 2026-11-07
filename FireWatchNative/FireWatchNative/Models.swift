import Foundation

struct Incident: Decodable, Identifiable {
    let id: String
    let title: String
    let description: String?
    let source: String
    let camera_id: String?
    let location_name: String?
    let lat: Double
    let lon: Double
    let severity: String
    let status: String
    let classification: String?
    let confidence: Double?
    let detection_mode: String
    let media_type: String?
    let media_url: String?
    let media_note: String?
    let is_demo: Bool
    let detection_id: String?
    let created_at: String
    let updated_at: String
}

struct Camera: Decodable, Identifiable {
    let id: String
    let name: String
    let url: String
    let lat: Double
    let lon: Double
    let status: String?
    let last_checked_at: String?
    let last_frame_at: String?
    let last_error: String?
    let snapshot_url: String?
}

struct Stats: Decodable {
    let fire_detections: Int?
    let smoke_detections: Int?
    let cameras_online: Int?
    let high_risk_zones: Int?
    let totalDetections: Int?
    let incidents: IncidentStats?

    enum CodingKeys: String, CodingKey {
        case fire_detections, smoke_detections, cameras_online, high_risk_zones
        case totalDetections = "total_detections"
        case incidents
    }
}

struct IncidentStats: Decodable {
    let total: Int?
    let active: Int?
    let by_severity: [String: Int]?
}

struct DetectorHealth: Decodable {
    let mode: String?
    let provider: String?
    let model_name: String?
    let disclaimer: String?
    let fallback_reason: String?
}

struct ServerHealth: Decodable {
    let status: String?
    let database: Bool?
    let ffmpeg: Bool?
    let detector: DetectorHealth?
    let firebase: String?
    let camera_auto_scan_enabled: Bool?
    let camera_auto_scan_active: Bool?
    let camera_auto_scan_interval_sec: Int?
    let cameras_configured: Int?
    let demo_videos_available: Int?
    let server_time: String?
}

struct DetectionSummary: Decodable {
    let id: String
    let status: String
    let classification: String
    let confidence: Double
    let mode: String
    let model_name: String
    let disclaimer: String
    let incident_id: String?
    let image_url: String
    let annotated_image_url: String?
    let processing_ms: Int
    let created_at: String
}

struct DeviceRegistration: Decodable {
    let ok: Bool
    let devices: Int?
    let firebase: String?
}
