import CoreML
import Vision
import UIKit
import ImageIO

struct OnDeviceFireResult {
    let fireDetected: Bool
    let smokeDetected: Bool
    let confidence: Float
    let objectCount: Int
    let modelName: String

    var classification: String {
        if fireDetected && smokeDetected { return "Огонь и дым" }
        if fireDetected { return "Огонь" }
        if smokeDetected { return "Дым" }
        return "Не обнаружены"
    }
}

enum OnDeviceFireError: LocalizedError {
    case missingModel
    case invalidImage
    case unsupportedOutputs
    case unsupportedLabels

    var errorDescription: String? {
        switch self {
        case .missingModel:
            return "Модель Core ML пока не установлена. Экспортируйте fire_smoke_yolov8n.pt и добавьте .mlpackage в Xcode."
        case .invalidImage:
            return "Не удалось прочитать фотографию."
        case .unsupportedOutputs:
            return "Core ML вернул неподдерживаемый тип данных. Требуется YOLO-экспорт с nms=True, совместимый с Vision."
        case .unsupportedLabels:
            return "Модель должна возвращать названия классов fire и smoke. Номера 0/1 без явного сопоставления нельзя интерпретировать: можно перепутать огонь и дым."
        }
    }
}

enum OnDeviceFireDetector {
    static let modelName = "fire_smoke_yolov8n"

    static var isInstalled: Bool {
        Bundle.main.url(forResource: modelName, withExtension: "mlmodelc") != nil
    }

    /// Still needs model validation against real non-fire/fire images.
    /// One image never establishes a confirmed wildfire incident.
    static func analyze(_ image: UIImage) async throws -> OnDeviceFireResult {
        guard let modelURL = Bundle.main.url(forResource: modelName, withExtension: "mlmodelc") else {
            throw OnDeviceFireError.missingModel
        }
        guard let cgImage = image.cgImage else {
            throw OnDeviceFireError.invalidImage
        }
        let orientation = cgOrientation(for: image.imageOrientation)
        return try await Task.detached(priority: .userInitiated) {
            let configuration = MLModelConfiguration()
            configuration.computeUnits = .all
            let model = try MLModel(contentsOf: modelURL, configuration: configuration)
            let visionModel = try VNCoreMLModel(for: model)
            let request = VNCoreMLRequest(model: visionModel)
            request.imageCropAndScaleOption = .scaleFit
            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
            try handler.perform([request])

            let results = request.results ?? []
            guard results.allSatisfy({ $0 is VNRecognizedObjectObservation }) else {
                throw OnDeviceFireError.unsupportedOutputs
            }
            let observations = results.compactMap { $0 as? VNRecognizedObjectObservation }
            var fire = false
            var smoke = false
            var highest: Float = 0
            var accepted = 0

            for observation in observations {
                guard let label = observation.labels.first else { continue }
                let key = label.identifier.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                // D-Fire exports may order numeric labels differently. Never guess.
                let fireLabel = key == "fire"
                let smokeLabel = key == "smoke"
                guard fireLabel || smokeLabel else { throw OnDeviceFireError.unsupportedLabels }
                guard label.confidence >= 0.65 else { continue }
                accepted += 1
                highest = max(highest, label.confidence)
                fire = fire || fireLabel
                smoke = smoke || smokeLabel
            }

            return OnDeviceFireResult(
                fireDetected: fire,
                smokeDetected: smoke,
                confidence: highest,
                objectCount: accepted,
                modelName: modelName
            )
        }.value
    }

    /// UIImage and Vision use different orientation enumerations.
    /// Preserve the photo's actual orientation before asking the model.
    private static func cgOrientation(for orientation: UIImage.Orientation) -> CGImagePropertyOrientation {
        switch orientation {
        case .up: return .up
        case .down: return .down
        case .left: return .left
        case .right: return .right
        case .upMirrored: return .upMirrored
        case .downMirrored: return .downMirrored
        case .leftMirrored: return .leftMirrored
        case .rightMirrored: return .rightMirrored
        @unknown default: return .up
        }
    }
}
