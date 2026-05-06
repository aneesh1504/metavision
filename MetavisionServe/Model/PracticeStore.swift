import Foundation
import UIKit

/// In-memory + disk-backed store for the current session's samples and generated reports.
/// Persistence via JSON + document directory for MVP; upgrade to SwiftData when targeting iOS 17+.
@MainActor
final class PracticeStore: ObservableObject {

    let sessionID = UUID()

    @Published private(set) var samples: [ServeSample] = []
    @Published private(set) var reports: [ServeBatchReport] = []

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init() {
        loadPersistedData()
    }

    // MARK: - Samples

    func addSample(_ sample: ServeSample) {
        samples.append(sample)
        persistSamples()
    }

    func updateSample(_ sample: ServeSample) {
        if let idx = samples.firstIndex(where: { $0.id == sample.id }) {
            samples[idx] = sample
            persistSamples()
        }
    }

    func deleteSample(id: UUID) {
        samples.removeAll { $0.id == id }
        persistSamples()
    }

    var confirmedSamples: [ServeSample] {
        samples.filter { $0.labelSource != .autoInferred }
    }

    // MARK: - Reports

    func addReport(_ report: ServeBatchReport) {
        reports.insert(report, at: 0)
        persistReports()
    }

    // MARK: - Frame images on disk

    func saveFrame(_ image: UIImage, filename: String) {
        guard let data = image.pngData() else { return }
        let url = framesDirectory.appendingPathComponent(filename)
        try? data.write(to: url, options: .atomic)
    }

    func loadFrame(filename: String) -> UIImage? {
        let url = framesDirectory.appendingPathComponent(filename)
        return UIImage(contentsOfFile: url.path)
    }

    // MARK: - Persistence

    private var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private var framesDirectory: URL {
        let dir = documentsDirectory.appendingPathComponent("frames")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func persistSamples() {
        let url = documentsDirectory.appendingPathComponent("samples.json")
        if let data = try? encoder.encode(samples) {
            try? data.write(to: url, options: .atomic)
        }
    }

    private func persistReports() {
        let url = documentsDirectory.appendingPathComponent("reports.json")
        if let data = try? encoder.encode(reports) {
            try? data.write(to: url, options: .atomic)
        }
    }

    func loadPersistedData() {
        let docs = documentsDirectory
        if let data = try? Data(contentsOf: docs.appendingPathComponent("samples.json")),
           let loaded = try? decoder.decode([ServeSample].self, from: data) {
            samples = loaded
        }
        if let data = try? Data(contentsOf: docs.appendingPathComponent("reports.json")),
           let loaded = try? decoder.decode([ServeBatchReport].self, from: data) {
            reports = loaded
        }
    }
}
