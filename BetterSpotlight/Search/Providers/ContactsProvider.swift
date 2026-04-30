import Foundation
import Contacts

@MainActor
final class ContactsProvider: SearchProvider {
    let category: SearchCategory = .contacts

    private let store = CNContactStore()
    nonisolated(unsafe) static var cached: [ContactInfo] = []

    /// Resolve a Messages handle (phone/email) to a full `ContactInfo`.
    /// Mirrors `MessagesProvider.name(forHandle:)` normalization.
    nonisolated static func contact(forHandle handle: String) -> ContactInfo? {
        let lowerEmail = handle.contains("@") ? handle.lowercased() : nil
        let phoneKey: String? = handle.contains("@") ? nil : {
            let digits = handle.filter { $0.isNumber }
            return digits.count > 10 ? String(digits.suffix(10)) : digits
        }()
        for c in cached {
            if let lowerEmail, c.emails.contains(where: { $0.lowercased() == lowerEmail }) {
                return c
            }
            if let phoneKey {
                for p in c.phoneNumbers {
                    let d = p.filter { $0.isNumber }
                    let key = d.count > 10 ? String(d.suffix(10)) : d
                    if key == phoneKey { return c }
                }
            }
        }
        return nil
    }

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
            CNContactOrganizationNameKey, CNContactJobTitleKey,
            CNContactPhoneNumbersKey, CNContactEmailAddressesKey,
            CNContactThumbnailImageDataKey, CNContactIdentifierKey,
            CNContactBirthdayKey, CNContactPostalAddressesKey,
            CNContactNoteKey,
        ].map { $0 as CNKeyDescriptor }
        let req = CNContactFetchRequest(keysToFetch: keys)
        var out: [ContactInfo] = []
        do {
            try store.enumerateContacts(with: req) { contact, _ in
                let name = [contact.givenName, contact.familyName]
                    .filter { !$0.isEmpty }.joined(separator: " ")
                guard !name.isEmpty || !contact.organizationName.isEmpty else { return }
                let display = name.isEmpty ? contact.organizationName : name
                let formatter = CNPostalAddressFormatter()
                let addresses = contact.postalAddresses
                    .map { formatter.string(from: $0.value) }
                    .filter { !$0.isEmpty }
                out.append(ContactInfo(
                    id: contact.identifier,
                    displayName: display,
                    phoneNumbers: contact.phoneNumbers.map { $0.value.stringValue },
                    emails: contact.emailAddresses.map { String($0.value) },
                    imageData: contact.thumbnailImageData,
                    organization: contact.organizationName.isEmpty ? nil
                                : contact.organizationName,
                    birthday: contact.birthday,
                    jobTitle: contact.jobTitle.isEmpty ? nil : contact.jobTitle,
                    addresses: addresses,
                    note: contact.note.isEmpty ? nil : contact.note
                ))
            }
        } catch {
            Log.warn("contacts: enumeration failed: \(error)", category: "contacts")
        }
        Self.cached = out.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        Log.info("contacts: cached \(Self.cached.count) entries", category: "contacts")
    }
}
