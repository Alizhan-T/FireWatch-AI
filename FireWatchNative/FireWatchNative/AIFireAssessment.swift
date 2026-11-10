import Foundation

/// Clear, evidence-first wording for structured detector results.
/// This is NOT a text-generating AI prompt and never fabricates a location,
/// cause, time, affected area, or a confirmation from one photograph.
enum AIFireAssessment {
    static func headline(for classification: String) -> String {
        switch classification {
        case "fire_smoke": return "Возможные признаки огня и дыма"
        case "fire": return "Возможные признаки огня"
        case "smoke": return "Возможные признаки дыма"
        case "none": return "Признаки огня и дыма не обнаружены"
        default: return "Результат не распознан"
        }
    }

    static func evidence(for classification: String) -> String {
        switch classification {
        case "fire_smoke":
            return "Алгоритм выделил на изображении области, похожие на пламя и дым. Это не подтверждает реальный пожар."
        case "fire":
            return "Алгоритм выделил область, похожую на пламя. Отражения, свет и другие объекты могут вызвать ложное срабатывание."
        case "smoke":
            return "Алгоритм выделил область, похожую на дым. Облака, туман и пыль могут выглядеть похоже."
        case "none":
            return "На этом кадре модель не выделила объекты выше своего порога. Это не означает, что опасности нет."
        default:
            return "Ответ модели содержит неизвестный тип объекта; его нельзя интерпретировать как пожар."
        }
    }

    static func score(_ confidence: Double, mode: String, classification: String) -> String {
        guard classification != "none" else {
            return "Оценка уверенности отсутствует: модель не вернула обнаружений выше порога."
        }
        if mode != "real_model" {
            return "Число от демо-эвристики не является вероятностью пожара или уверенностью нейросети."
        }
        let percent = Int((min(max(confidence, 0), 1) * 100).rounded())
        return "Оценка модели: \(percent)%. Это score распознавания объекта, а не вероятность реального пожара."
    }

    static func status(mode: String) -> String {
        mode == "real_model"
            ? "AI · реальная модель (предварительный анализ)"
            : "DEMO · проверка по цветам, без нейросети"
    }

    static func action(for classification: String, mode: String) -> String {
        guard mode == "real_model" else {
            return "Для реальной оценки подключите обученную модель YOLO или проверенный Core ML. Демо-эвристика не предназначена для оповещения."
        }
        if classification == "none" {
            return "При подозрении на опасность проверьте другие кадры, ракурс и качество изображения. Одного кадра недостаточно для вывода."
        }
        if !["fire", "smoke", "fire_smoke"].contains(classification) {
            return "Проверьте настройки модели и повторите анализ."
        }
        return "Проверьте исходный кадр, соседние кадры и источник сигнала. Решение об инциденте принимает человек; приложение не вызывает службы спасения."
    }
}
