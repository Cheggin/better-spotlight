import Foundation

@MainActor
protocol SearchProvider: AnyObject {
    var category: SearchCategory { get }
    func search(query: String) async throws -> [SearchResult]
    func cancel()
}
