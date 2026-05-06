import Foundation

struct Drill: Identifiable, Codable {
    let id: String
    let title: String
    let trigger: String
    let description: String
    let durationMinutes: Int
}

final class DrillLibrary {
    static let shared = DrillLibrary()

    private let allDrills: [Drill]

    private init() {
        guard let url = Bundle.main.url(forResource: "Drills", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let drills = try? JSONDecoder().decode([Drill].self, from: data) else {
            allDrills = []
            return
        }
        allDrills = drills
    }

    func drills(for ids: [String]) -> [Drill] {
        allDrills.filter { ids.contains($0.id) }
    }
}
