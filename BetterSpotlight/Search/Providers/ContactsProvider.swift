import Foundation
import Contacts

@MainActor
final class ContactsProvider: SearchProvider {
    let category: SearchCategory = .contacts

    private let store = CNContactStore()
    private static var cached: [ContactInfo] = []

    func search(query rawQuery: String) async throws -> [SearchResult] {
        await prefetch()
        let q = rawQuery.trimmingCharacters(in: .whitespaces).lowercased()
        let pool = Self.cached
        let filtered = q.isEmpty
            ? Array(pool.prefix(50))
            : pool.filter { c in
                c.displayName.lowercased().contains(q) ||
                c.phoneNumbers.contains(where: { $0.lowercased().contains(q) }) ||
                c.emails.contains(where: { $0.lowercased().contains(q) })
            }
        return filtered.map { c in
            SearchResult(
                id: "contact:\(c.id)",
                title: c.displayName,
                subtitle: c.primaryHandle,
                trailingText: c.organization,
                iconName: "person.crop.circle.fill",
                category: .contacts,
                payload: .contact(c),
                score: q.isEmpty ? 0.4
                    : (FuzzyMatcher.score(query: q, candidate: c.displayName) ?? 0.30)
            )
        }
    }

    func cancel() {}

    private func prefetch() async {
        let status = CNContactStore.authorizationStatus(for: .contacts)
        if status == .notDetermined {
            do { _ = try await store.requestAccess(for: .contacts) }
            catch { Log.warn("contacts: requestAccess failed: \(error)", category: "contacts") }
        }
        guard CNContactStore.authorizationStatus(for: .contacts) == .authorized else { return }
        guard Self.cached.isEmpty else { return }

        let keys: [CNKeyDescriptor] = [
            CNContactGivenNameKey, CNContactFamilyNameKey,
            CNContactOrganizationNameKey,
            CNContactPhoneNumbersKey, CNContactEmailAddressesKey,
            CNContactThumbnailImageDataKey, CNContactIdentifierKey,
        ].map { $0 as CNKeyDescriptor }
        let req = CNContactFetchRequest(keysToFetch: keys)
        var out: [ContactInfo] = []
        do {
            try store.enumerateContacts(with: req) { contact, _ in
                let name = [contact.givenName, contact.familyName]
                    .filter { !$0.isEmpty }.joined(separator: " ")
                guard !name.isEmpty || !contact.organizationName.isEmpty else { return }
                let display = name.isEmpty ? contact.organizationName : name
                out.append(ContactInfo(
                    id: contact.identifier,
                    displayName: display,
                    phoneNumbers: contact.phoneNumbers.map { $0.value.stringValue },
                    emails: contact.emailAddresses.map { String($0.value) },
                    imageData: contact.thumbnailImageData,
                    organization: contact.organizationName.isEmpty ? nil
                                : contact.organizationName
                ))
            }
        } catch {
            Log.warn("contacts: enumeration failed: \(error)", category: "contacts")
        }
        Self.cached = out.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        Log.info("contacts: cached \(Self.cached.count) entries", category: "contacts")
    }
}
