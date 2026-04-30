import SwiftUI
import AppKit
import Contacts

/// Contacts center pane: editable contact form. Reads from Contacts.framework,
/// stages changes into a CNMutableContact, and writes back via CNSaveRequest
/// when the user clicks Save.
struct ContactEditPane: View {
    let contact: ContactInfo?
    let googleSession: GoogleSession

    @State private var draft: ContactDraft = .empty
    @State private var saving = false
    @State private var savedFlash = false
    @State private var error: String?

    var body: some View {
        if let contact {
            content(for: contact)
                .onChange(of: contact.id) { _, _ in
                    draft = ContactDraft(from: contact)
                    error = nil
                }
                .onAppear { draft = ContactDraft(from: contact) }
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        VStack(spacing: Tokens.Space.sm) {
            Spacer()
            Image(systemName: "person.crop.circle")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(Tokens.Color.textTertiary)
            Text("Select a contact to edit")
                .font(.system(size: 13))
                .foregroundStyle(Tokens.Color.textSecondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func content(for contact: ContactInfo) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Space.lg) {
                HStack(spacing: Tokens.Space.md) {
                    avatar(for: contact, size: 72)
                    VStack(alignment: .leading, spacing: 6) {
                        TextField("First name", text: $draft.givenName)
                            .textFieldStyle(.plain)
                            .font(.system(size: 22, weight: .semibold))
                        TextField("Organization", text: $draft.organization)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13))
                            .foregroundStyle(Tokens.Color.textTertiary)
                    }
                }

                section(title: "PHONE") {
                    ForEach(draft.phones.indices, id: \.self) { idx in
                        editableRow(
                            icon: "phone.fill",
                            text: $draft.phones[idx],
                            placeholder: "Phone number",
                            onRemove: { draft.phones.remove(at: idx) }
                        )
                    }
                    addButton(label: "Add phone") { draft.phones.append("") }
                }

                section(title: "EMAIL") {
                    ForEach(draft.emails.indices, id: \.self) { idx in
                        editableRow(
                            icon: "envelope.fill",
                            text: $draft.emails[idx],
                            placeholder: "email@example.com",
                            onRemove: { draft.emails.remove(at: idx) }
                        )
                    }
                    addButton(label: "Add email") { draft.emails.append("") }
                }

                if let error {
                    Text(error)
                        .font(.system(size: 12))
                        .foregroundStyle(.red)
                }

                HStack {
                    Spacer()
                    if savedFlash {
                        Text("Saved")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.green)
                    }
                    Button {
                        save(contact)
                    } label: {
                        Text(saving ? "Saving…" : "Save")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(Tokens.Color.accent))
                    }
                    .buttonStyle(PressableStyle())
                    .disabled(saving)
                }
            }
            .padding(Tokens.Space.lg)
        }
        .scrollIndicators(.hidden)
    }

    @ViewBuilder
    private func avatar(for c: ContactInfo, size: CGFloat) -> some View {
        if let data = c.imageData, let img = NSImage(data: data) {
            Image(nsImage: img).resizable().interpolation(.high)
                .aspectRatio(contentMode: .fill)
                .frame(width: size, height: size)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
        } else {
            ZStack {
                Circle().fill(Tokens.Color.contactTint.opacity(0.18))
                Text(c.initials)
                    .font(.system(size: size * 0.36, weight: .semibold))
                    .foregroundStyle(Tokens.Color.contactTint)
            }
            .frame(width: size, height: size)
        }
    }

    @ViewBuilder
    private func section<Content: View>(title: String,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.7)
                .foregroundStyle(Tokens.Color.textTertiary)
            VStack(spacing: 6) { content() }
        }
    }

    @ViewBuilder
    private func editableRow(icon: String,
                             text: Binding<String>,
                             placeholder: String,
                             onRemove: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Tokens.Color.contactTint)
                .frame(width: 18)
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
            Button(action: onRemove) {
                Image(systemName: "minus.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Tokens.Color.textTertiary)
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Tokens.Color.hairline, lineWidth: 0.5)
        )
    }

    private func addButton(label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "plus.circle.fill")
                Text(label)
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Tokens.Color.accent)
        }
        .buttonStyle(.borderless)
    }

    // MARK: - Save

    private func save(_ contact: ContactInfo) {
        saving = true
        error = nil
        Task {
            do {
                let store = CNContactStore()
                let cnContact = try store.unifiedContact(
                    withIdentifier: contact.id,
                    keysToFetch: [
                        CNContactGivenNameKey, CNContactFamilyNameKey,
                        CNContactOrganizationNameKey,
                        CNContactPhoneNumbersKey, CNContactEmailAddressesKey,
                    ].map { $0 as CNKeyDescriptor }
                ).mutableCopy() as! CNMutableContact

                cnContact.givenName = draft.givenName
                cnContact.familyName = draft.familyName
                cnContact.organizationName = draft.organization
                cnContact.phoneNumbers = draft.phones
                    .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                    .map { CNLabeledValue(label: CNLabelHome,
                                          value: CNPhoneNumber(stringValue: $0)) }
                cnContact.emailAddresses = draft.emails
                    .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                    .map { CNLabeledValue(label: CNLabelHome, value: $0 as NSString) }

                let req = CNSaveRequest()
                req.update(cnContact)
                try store.execute(req)

                await MainActor.run {
                    saving = false
                    savedFlash = true
                    Log.info("contacts: saved \(contact.id)", category: "contacts")
                    Task {
                        try? await Task.sleep(nanoseconds: 1_500_000_000)
                        savedFlash = false
                    }
                }
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    saving = false
                }
            }
        }
    }
}

private struct ContactDraft {
    var givenName: String
    var familyName: String
    var organization: String
    var phones: [String]
    var emails: [String]

    static let empty = ContactDraft(givenName: "", familyName: "",
                                    organization: "", phones: [], emails: [])

    init(givenName: String, familyName: String, organization: String,
         phones: [String], emails: [String]) {
        self.givenName = givenName
        self.familyName = familyName
        self.organization = organization
        self.phones = phones
        self.emails = emails
    }

    init(from c: ContactInfo) {
        let parts = c.displayName.split(separator: " ", maxSplits: 1).map(String.init)
        self.givenName = parts.first ?? ""
        self.familyName = parts.count > 1 ? parts[1] : ""
        self.organization = c.organization ?? ""
        self.phones = c.phoneNumbers
        self.emails = c.emails
    }
}

// MARK: - Right pane: recent interactions

struct ContactRecentInteractionsPane: View {
    let contact: ContactInfo

    @State private var recentMessages: [ChatMessage] = []
    @State private var loading = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Space.md) {
                Text("RECENT")
                    .font(Tokens.Typeface.micro)
                    .tracking(0.7)
                    .foregroundStyle(Tokens.Color.contactTint)

                Text(contact.displayName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Tokens.Color.textPrimary)

                actionRow

                Divider().opacity(0.4)

                if loading {
                    ProgressView()
                } else if recentMessages.isEmpty {
                    Text("No recent messages")
                        .font(.system(size: 12))
                        .foregroundStyle(Tokens.Color.textTertiary)
                } else {
                    Text("MESSAGES")
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(0.7)
                        .foregroundStyle(Tokens.Color.textTertiary)
                    VStack(spacing: 6) {
                        ForEach(recentMessages.prefix(8), id: \.id) { msg in
                            HStack(alignment: .top, spacing: 8) {
                                Circle()
                                    .fill(msg.isFromMe ? Tokens.Color.accent : Tokens.Color.contactTint)
                                    .frame(width: 6, height: 6)
                                    .padding(.top, 6)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(msg.text)
                                        .font(.system(size: 12))
                                        .foregroundStyle(Tokens.Color.textPrimary)
                                        .lineLimit(2)
                                    Text(msg.relativeDate)
                                        .font(.system(size: 10))
                                        .foregroundStyle(Tokens.Color.textTertiary)
                                }
                            }
                        }
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(Tokens.Space.lg)
        }
        .scrollIndicators(.hidden)
        .task(id: contact.id) { await loadRecent() }
    }

    private var actionRow: some View {
        HStack(spacing: 8) {
            if let phone = contact.phoneNumbers.first {
                interactionButton(
                    icon: "phone.fill",
                    label: "Call",
                    color: Tokens.Color.accent
                ) {
                    if let url = URL(string: "tel:\(phone.filter { !$0.isWhitespace })") {
                        NSWorkspace.shared.open(url)
                    }
                }
                interactionButton(
                    icon: "bubble.left.fill",
                    label: "Message",
                    color: Tokens.Color.contactTint
                ) {
                    let recipient = phone.addingPercentEncoding(
                        withAllowedCharacters: .urlPathAllowed) ?? phone
                    if let url = URL(string: "sms:\(recipient)") {
                        NSWorkspace.shared.open(url)
                    }
                }
                interactionButton(
                    icon: "video.fill",
                    label: "FaceTime",
                    color: Tokens.Color.fileTint
                ) {
                    if let url = URL(string: "facetime://\(phone)") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
            if let email = contact.emails.first {
                interactionButton(
                    icon: "envelope.fill",
                    label: "Email",
                    color: Tokens.Color.mailTint
                ) {
                    if let url = URL(string: "mailto:\(email)") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }
    }

    private func interactionButton(icon: String, label: String,
                                   color: Color,
                                   action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(color.opacity(0.14)))
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Tokens.Color.textSecondary)
            }
        }
        .buttonStyle(PressableStyle())
    }

    @MainActor
    private func loadRecent() async {
        loading = true
        defer { loading = false }
        recentMessages = []
        // Try each handle until we find one with messages.
        for handle in contact.phoneNumbers + contact.emails {
            if let thread = try? MessagesProvider.fetchThread(forHandle: handle, max: 8),
               !thread.isEmpty {
                recentMessages = thread.reversed()
                return
            }
        }
    }
}

// MARK: - Right pane: contact info derived from a Messages handle

struct ContactDetailFromMessage: View {
    let message: ChatMessage

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Space.md) {
                Text("CONTACT")
                    .font(Tokens.Typeface.micro)
                    .tracking(0.7)
                    .foregroundStyle(Tokens.Color.contactTint)

                HStack(spacing: Tokens.Space.md) {
                    avatar(size: 56)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(message.displayName)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Tokens.Color.textPrimary)
                            .lineLimit(2)
                        Text(message.handle)
                            .font(.system(size: 12))
                            .foregroundStyle(Tokens.Color.textTertiary)
                    }
                }

                Button {
                    let recipient = message.handle.addingPercentEncoding(
                        withAllowedCharacters: .urlPathAllowed) ?? message.handle
                    if let url = URL(string: "sms:\(recipient)") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "bubble.left.and.bubble.right.fill")
                        Text("Open in Messages").font(Tokens.Typeface.bodyEmphasis)
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, Tokens.Space.md)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Tokens.Color.accent)
                    )
                }
                .buttonStyle(PressableStyle())

                Spacer(minLength: 0)
            }
            .padding(Tokens.Space.lg)
        }
        .scrollIndicators(.hidden)
    }

    @ViewBuilder
    private func avatar(size: CGFloat) -> some View {
        if let data = MessagesProvider.imageData(forHandle: message.handle),
           let img = NSImage(data: data) {
            Image(nsImage: img).resizable().interpolation(.high)
                .aspectRatio(contentMode: .fill)
                .frame(width: size, height: size)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
        } else {
            ZStack {
                Circle().fill(Tokens.Color.contactTint.opacity(0.18))
                Text(message.initials)
                    .font(.system(size: size * 0.36, weight: .semibold))
                    .foregroundStyle(Tokens.Color.contactTint)
            }
            .frame(width: size, height: size)
        }
    }
}

// MARK: - Mail right pane

struct MailSenderCard: View {
    let message: MailMessage

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Space.md) {
                Text("FROM")
                    .font(Tokens.Typeface.micro)
                    .tracking(0.7)
                    .foregroundStyle(Tokens.Color.mailTint)

                HStack(spacing: Tokens.Space.md) {
                    SenderAvatar(email: message.fromEmail,
                                 displayName: message.fromName,
                                 size: 56)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(message.fromName)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Tokens.Color.textPrimary)
                            .lineLimit(2)
                        Text(message.fromEmail)
                            .font(.system(size: 12))
                            .foregroundStyle(Tokens.Color.textTertiary)
                    }
                }

                Button {
                    let url = URL(string: "https://mail.google.com/mail/u/0/#inbox/\(message.id)")!
                    NSWorkspace.shared.open(url)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "envelope.fill")
                        Text("Open in Gmail").font(Tokens.Typeface.bodyEmphasis)
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, Tokens.Space.md)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Tokens.Color.accent)
                    )
                }
                .buttonStyle(PressableStyle())

                Spacer(minLength: 0)
            }
            .padding(Tokens.Space.lg)
        }
        .scrollIndicators(.hidden)
    }
}
