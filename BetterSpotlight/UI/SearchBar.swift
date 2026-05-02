import SwiftUI
import AppKit

struct SearchBar: View {
    @Binding var query: String
    var onSubmit: () -> Void
    var onEscape: () -> Void

    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: Tokens.Space.sm) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Tokens.Color.textSecondary)
                .frame(width: 22)

            FocusedTextField(text: $query,
                             placeholder: "Search files, mail, calendar…",
                             onSubmit: onSubmit,
                             onEscape: onEscape)
                .focused($focused)
                .frame(height: 28)

            Spacer(minLength: Tokens.Space.xs)

            HStack(spacing: 6) {
                ToolbarLineIcon(systemName: "calendar", tooltip: "Open Google Calendar",
                                url: URL(string: "https://calendar.google.com/"))
                ToolbarLineIcon(systemName: "envelope", tooltip: "Open Gmail",
                                url: URL(string: "https://mail.google.com/"))
                ToolbarSettingsButton()
            }
        }
        .padding(.horizontal, Tokens.Space.sm)
        .padding(.vertical, Tokens.Space.xs)
        .onAppear { focused = true }
    }
}

/// Gear button — opens the Settings window and dismisses the spotlight panel.
private struct ToolbarSettingsButton: View {
    @EnvironmentObject var googleSession: GoogleSession
    @EnvironmentObject var preferences: Preferences
    @State private var hovering = false

    var body: some View {
        Button {
            NotificationCenter.default.post(name: .dismissSpotlight, object: nil)
            SettingsWindowController.shared.show(
                googleSession: googleSession,
                preferences: preferences
            )
        } label: {
            Image(systemName: "gearshape")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(Tokens.Color.textSecondary)
                .frame(width: 32, height: 32)
                .background(
                    Circle().fill(hovering ? Color.black.opacity(0.05) : .clear)
                )
                .overlay(
                    Circle().strokeBorder(Tokens.Color.hairline, lineWidth: 0.5)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .onHover { hovering = $0 }
        .overlay(alignment: .bottom) {
            if hovering {
                ToolbarTooltip(text: "Settings")
                    .offset(y: 22)
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }
        }
        .animation(.easeOut(duration: 0.25), value: hovering)
    }
}

/// Monochrome circular line-icon button for the top-right toolbar.
/// Matches the reference: thin hairline outline, monochrome glyph, hover fill.
private struct ToolbarLineIcon: View {
    let systemName: String
    var tooltip: String = ""
    let url: URL?
    @State private var hovering = false

    var body: some View {
        Button {
            if let url { NSWorkspace.shared.open(url) }
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(Tokens.Color.textSecondary)
                .frame(width: 32, height: 32)
                .background(
                    Circle().fill(hovering ? Color.black.opacity(0.05) : .clear)
                )
                .overlay(
                    Circle().strokeBorder(Tokens.Color.hairline, lineWidth: 0.5)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .onHover { hovering = $0 }
        .overlay(alignment: .bottom) {
            if hovering, !tooltip.isEmpty {
                ToolbarTooltip(text: tooltip)
                    .offset(y: 22)
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }
        }
        .animation(.easeOut(duration: 0.25), value: hovering)
    }
}

private struct ToolbarTooltip: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(Tokens.Color.textSecondary)
            .fixedSize()
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(Tokens.Color.surfaceSunken))
            .overlay(Capsule().strokeBorder(Tokens.Color.hairline, lineWidth: 0.5))
    }
}

/// AppKit-backed text field with first-responder focus, submit, and escape handling.
private struct FocusedTextField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var onSubmit: () -> Void
    var onEscape: () -> Void

    func makeNSView(context: Context) -> NSTextField {
        let field = BorderlessTextField()
        field.placeholderString = placeholder
        field.font = NSFont.systemFont(ofSize: 18, weight: .regular)
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.textColor = NSColor(Tokens.Color.textPrimary)
        field.delegate = context.coordinator
        field.target = context.coordinator
        field.action = #selector(Coordinator.submit(_:))
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        if nsView.stringValue != text { nsView.stringValue = text }
        if let editor = nsView.window?.firstResponder as? NSTextView,
           editor.delegate === nsView {
            // already focused
        } else {
            DispatchQueue.main.async { nsView.window?.makeFirstResponder(nsView) }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: FocusedTextField
        init(_ parent: FocusedTextField) { self.parent = parent }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func control(_ control: NSControl,
                     textView: NSTextView,
                     doCommandBy commandSelector: Selector) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.cancelOperation(_:)):
                parent.onEscape(); return true
            case #selector(NSResponder.insertNewline(_:)):
                parent.onSubmit(); return true
            default:
                return false
            }
        }

        @objc func submit(_ sender: Any?) { parent.onSubmit() }
    }
}

private final class BorderlessTextField: NSTextField {
    override var allowsVibrancy: Bool { false }
}
