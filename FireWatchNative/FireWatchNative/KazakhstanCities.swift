import Foundation

/// Centroids for display and demo placement, NOT exact fire coordinates.
/// Choosing a city never claims to locate a fire inside that city.
struct KazakhstanCity: Identifiable, Hashable {
    let id: String
    let name: String
    let lat: Double
    let lon: Double
}

enum KazakhstanCities {
    static let all: [KazakhstanCity] = [
        .init(id: "astana", name: "Астана", lat: 51.1694, lon: 71.4491),
        .init(id: "almaty", name: "Алматы", lat: 43.2389, lon: 76.8897),
        .init(id: "semey", name: "Семей", lat: 50.4111, lon: 80.2275),
        .init(id: "aktau", name: "Актау", lat: 43.6532, lon: 51.1975),
        .init(id: "shymkent", name: "Шымкент", lat: 42.3154, lon: 69.5869),
        .init(id: "karaganda", name: "Караганда", lat: 49.8060, lon: 73.0850),
        .init(id: "pavlodar", name: "Павлодар", lat: 52.2873, lon: 76.9674),
        .init(id: "oskemen", name: "Өскемен", lat: 49.9483, lon: 82.6280),
        .init(id: "kostanay", name: "Костанай", lat: 53.2198, lon: 63.6354),
        .init(id: "atyrau", name: "Атырау", lat: 47.0945, lon: 51.9238),
        .init(id: "aktobe", name: "Актобе", lat: 50.2839, lon: 57.1670),
        .init(id: "taraz", name: "Тараз", lat: 42.8984, lon: 71.3975),
        .init(id: "kyzylorda", name: "Кызылорда", lat: 44.8479, lon: 65.5092),
        .init(id: "oral", name: "Орал", lat: 51.2278, lon: 51.3865),
        .init(id: "petropavl", name: "Петропавл", lat: 54.8728, lon: 69.1430),
        .init(id: "taldykorgan", name: "Талдыкорган", lat: 45.0177, lon: 78.3791),
        .init(id: "turkistan", name: "Туркестан", lat: 43.3019, lon: 68.2692),
        .init(id: "ekibastuz", name: "Экибастуз", lat: 51.7297, lon: 75.3266)
    ]

    static func find(_ id: String) -> KazakhstanCity {
        all.first(where: { $0.id == id }) ?? all[0]
    }

    static func name(for id: String) -> String {
        find(id).name
    }
}
