import Foundation

@MainActor
final class SpotlightEscapeStack: ObservableObject {
    typealias Handler = () -> Bool

    private var entries: [(id: UUID, handler: Handler)] = []

    func push(_ handler: @escaping Handler) -> UUID {
        let id = UUID()
        entries.append((id, handler))
        return id
    }

    func remove(_ id: UUID?) {
        guard let id else { return }
        entries.removeAll { $0.id == id }
    }

    func handleEscape() -> Bool {
        for entry in entries.reversed() {
            if entry.handler() {
                remove(entry.id)
                return true
            }
        }
        return false
    }
}
