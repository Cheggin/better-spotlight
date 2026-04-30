import SwiftUI
import AppKit

/// Center pane on the Messages tab: full-thread chat view for the selected
/// conversation. Messages render as iMessage-style bubbles, newest at the
/// bottom. Tapping the avatar / header opens the conversation in
/// Messages.app.
struct MessagesThreadView: View {
    let message: ChatMessage?

    @State private var thread: [ChatMessage] = []
    @State private var isLoading = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let m = message {
                header(for: m)
                    .padding(.horizontal, Tokens.Space.md)
                    .padding(.vertical, Tokens.Space.sm)
                Divider().opacity(0.45)
                threadView(for: m)
                Divider().opacity(0.45)
                MessagesReplyBox(message: m) {
                    Task { await refreshAfterSend() }
                }
                .padding(.horizontal, Tokens.Space.md)
                .padding(.vertical, Tokens.Space.sm)
            } else {
                placeholder
            }
        }
        .task(id: message?.handle) { await loadThread() }
        .task(id: message?.handle) { await pollWhileVisible() }
    }

    /// Re-reads chat.db a few times after a send. The Messages agent commits
    /// the outgoing row asynchronously, so an immediate reload often misses
    /// it; we re-check at 0/500ms/1500ms/3000ms.
    private func refreshAfterSend() async {
        for delay in [UInt64(0), 500_000_000, 1_500_000_000, 3_000_000_000] {
            if delay > 0 { try? await Task.sleep(nanoseconds: delay) }
            await loadThread()
        }
    }

    /// Light background poll so incoming messages / tapbacks appear while the
    /// thread is open without forcing the user to reopen the panel.
    private func pollWhileVisible() async {
        while !Task.isCancelled, message != nil {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            if Task.isCancelled { break }
            await loadThread()
        }
    }

    // MARK: Header

    private func header(for m: ChatMessage) -> some View {
        HStack(spacing: Tokens.Space.sm) {
            ContactAvatar(handle: m.handle, displayName: m.displayName, size: 36)
            VStack(alignment: .leading, spacing: 0) {
                Text(m.displayName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Tokens.Color.textPrimary)
                Text(m.handle)
                    .font(.system(size: 11))
                    .foregroundStyle(Tokens.Color.textTertiary)
            }
            Spacer()
            Button {
                let recipient = m.handle.addingPercentEncoding(
                    withAllowedCharacters: .urlPathAllowed) ?? m.handle
                if let url = URL(string: "sms:\(recipient)") {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                Text("Open")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Tokens.Color.accent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Tokens.Color.accentSoft))
            }
            .buttonStyle(PressableStyle())
        }
    }

    // MARK: Thread

    private func threadView(for selected: ChatMessage) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 6) {
                    if isLoading && thread.isEmpty {
                        ProgressView().padding(.top, Tokens.Space.xl)
                    }
                    if let error {
                        Text(error)
                            .font(.system(size: 12))
                            .foregroundStyle(.red)
                            .padding(Tokens.Space.md)
                    }
                    ForEach(Array(thread.enumerated()), id: \.element.id) { idx, msg in
                        if shouldShowDivider(at: idx) {
                            DateDivider(date: msg.date)
                                .padding(.top, 8)
                        }
                        Bubble(message: msg)
                            .id(msg.id)
                    }
                    Color.clear.frame(height: 8).id("bottom")
                }
                .padding(.horizontal, Tokens.Space.md)
                .padding(.vertical, Tokens.Space.sm)
            }
            .scrollIndicators(.hidden)
            .onChange(of: thread.count) { _, _ in
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
        }
    }

    private func shouldShowDivider(at idx: Int) -> Bool {
        guard idx > 0 else { return true }
        let prev = thread[idx - 1].date
        let curr = thread[idx].date
        return !Calendar.current.isDate(prev, inSameDayAs: curr)
    }

    private var placeholder: some View {
        VStack(spacing: Tokens.Space.sm) {
            Spacer()
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(Tokens.Color.textTertiary)
            Text("Select a conversation to view")
                .font(.system(size: 13))
                .foregroundStyle(Tokens.Color.textSecondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Loading

    @MainActor
    private func loadThread() async {
        guard let m = message else {
            thread = []
            return
        }
        isLoading = true
        error = nil
        let handle = m.handle
        do {
            let result = try await Task.detached {
                try MessagesProvider.fetchThread(forHandle: handle, max: 200)
            }.value
            thread = result
        } catch let err as MessagesError {
            error = err.localizedDescription
            thread = []
        } catch {
            self.error = error.localizedDescription
            thread = []
        }
        isLoading = false
    }
}

// MARK: - Reply box

struct MessagesReplyBox: View {
    let message: ChatMessage
    var onSent: () -> Void = {}

    @State private var replyText = ""
    @State private var sending = false
    @State private var sendError: String?
    @State private var sentFlash = false

    private var contact: ContactInfo? {
        ContactsProvider.contact(forHandle: message.handle)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .bottom, spacing: 8) {
                TextField("iMessage \(contact?.displayName.split(separator: " ").first.map(String.init) ?? message.displayName)…",
                          text: $replyText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...4)
                    .font(.system(size: 13))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.white)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Tokens.Color.hairline, lineWidth: 0.5)
                    )
                    .onSubmit { send() }

                Button(action: send) {
                    Image(systemName: sending ? "ellipsis" : "arrow.up")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(
                            Circle().fill(canSend ? Tokens.Color.accent
                                                  : Tokens.Color.accent.opacity(0.4))
                        )
                }
                .buttonStyle(PressableStyle())
                .disabled(!canSend)
            }

            HStack(spacing: 8) {
                if sentFlash {
                    Label("Sent", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.green)
                }
                if let err = sendError {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(err)
                            .font(.system(size: 11))
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                        if err.contains("tccutil") {
                            HStack(spacing: 8) {
                                Button("Copy fix command") {
                                    let pb = NSPasteboard.general
                                    pb.clearContents()
                                    pb.setString("tccutil reset AppleEvents com.reagan.betterspotlight",
                                                 forType: .string)
                                }
                                Button("Open Settings") {
                                    MessagesSender.openAutomationSettings()
                                }
                            }
                            .buttonStyle(.borderless)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Tokens.Color.accent)
                        }
                    }
                }
                Spacer()
                Button {
                    let recipient = message.handle.addingPercentEncoding(
                        withAllowedCharacters: .urlPathAllowed) ?? message.handle
                    if let url = URL(string: "sms:\(recipient)") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Text("Open in Messages")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Tokens.Color.accent)
                }
                .buttonStyle(.borderless)
            }
        }
    }

    private var canSend: Bool {
        !sending && !replyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func send() {
        guard canSend else { return }
        let body = replyText
        sending = true
        sendError = nil
        Task {
            do {
                try await MessagesSender.send(text: body, toHandle: message.handle)
                await MainActor.run {
                    replyText = ""
                    sentFlash = true
                    sending = false
                    onSent()
                    Task {
                        try? await Task.sleep(nanoseconds: 1_500_000_000)
                        sentFlash = false
                    }
                }
            } catch {
                await MainActor.run {
                    sendError = error.localizedDescription
                    sending = false
                }
            }
        }
    }
}

// MARK: - Bubble

private struct Bubble: View {
    let message: ChatMessage

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            if message.isFromMe { Spacer(minLength: 40) }
            VStack(alignment: message.isFromMe ? .trailing : .leading, spacing: 2) {
                Text(message.text)
                    .font(.system(size: 13))
                    .foregroundStyle(message.isFromMe ? .white : Tokens.Color.textPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(message.isFromMe
                                  ? Tokens.Color.accent
                                  : Color(red: 0.93, green: 0.94, blue: 0.96))
                    )
                Text(timeLabel)
                    .font(.system(size: 9))
                    .monospacedDigit()
                    .foregroundStyle(Tokens.Color.textTertiary)
                    .padding(.horizontal, 4)
            }
            if !message.isFromMe { Spacer(minLength: 40) }
        }
    }

    private var timeLabel: String {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f.string(from: message.date)
    }
}

// MARK: - Date divider

private struct DateDivider: View {
    let date: Date
    var body: some View {
        HStack {
            Spacer()
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(Tokens.Color.textTertiary)
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .background(Capsule().fill(Tokens.Color.surfaceSunken))
            Spacer()
        }
    }
    private var label: String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "TODAY" }
        if cal.isDateInYesterday(date) { return "YESTERDAY" }
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMM d"
        return f.string(from: date).uppercased()
    }
}

// MARK: - Avatar

private struct ContactAvatar: View {
    let handle: String
    let displayName: String
    let size: CGFloat
    var body: some View {
        if let data = MessagesProvider.imageData(forHandle: handle),
           let img = NSImage(data: data) {
            Image(nsImage: img).resizable().interpolation(.high)
                .aspectRatio(contentMode: .fill)
                .frame(width: size, height: size)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
        } else {
            ZStack {
                Circle().fill(Tokens.Color.contactTint.opacity(0.18))
                Text(initials)
                    .font(.system(size: size * 0.36, weight: .semibold))
                    .foregroundStyle(Tokens.Color.contactTint)
            }
            .frame(width: size, height: size)
        }
    }
    private var initials: String {
        let parts = displayName.split(separator: " ").prefix(2)
        let i = parts.compactMap { $0.first }.map(String.init).joined()
        return (i.isEmpty ? String(displayName.prefix(1)) : i).uppercased()
    }
}
