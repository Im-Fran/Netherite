import SwiftUI

/// Short, skippable first-run tour (5 pages). Reopen it from Help › Welcome Tour.
struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var page = 0
    @AccessibilityFocusState private var titleFocused: Bool

    struct Page: Identifiable {
        var id: Int
        var symbol: String
        var color: Color
        var title: LocalizedStringKey
        var text: LocalizedStringKey
        var points: [(String, LocalizedStringKey)]
    }

    #if os(macOS)
    static let shortcutPoints: [(String, LocalizedStringKey)] = [("magnifyingglass", "⌘O jumps to any note"), ("command", "⌘P finds any command"), ("square.and.arrow.up", "Clip web pages from the share sheet")]
    #else
    static let shortcutPoints: [(String, LocalizedStringKey)] = [("magnifyingglass", "Go to File jumps to any note"), ("command", "The command palette finds any command"), ("square.and.arrow.up", "Clip web pages from the share sheet")]
    #endif

    static let pages: [Page] = [
        Page(id: 0, symbol: "diamond.fill", color: .accentColor, title: "Welcome to Netherite",
             text: "A private home for your ideas. Every note is a plain Markdown file in a folder you own.",
             points: [("lock", "Your notes stay on your devices"), ("doc.text", "Open files, readable by any app"), ("icloud", "Sync through iCloud Drive if you want")]),
        Page(id: 1, symbol: "link", color: .purple, title: "Connect Your Thinking",
             text: "Link notes with [[double brackets]]. Backlinks and the graph show how your ideas relate.",
             points: [("arrow.uturn.backward", "Backlinks list every note that mentions this one"), ("point.3.connected.trianglepath.dotted", "The graph maps your whole vault"), ("number", "Tags and properties add structure")]),
        Page(id: 2, symbol: "text.cursor", color: .blue, title: "Write Without Friction",
             text: "Live Preview formats as you type, and shows the Markdown only on the line you're editing.",
             points: [("checklist", "Tasks, callouts and tables"), ("function", "Math and Mermaid diagrams"), ("slash.circle", "Type / to insert anything")]),
        Page(id: 3, symbol: "rectangle.3.group", color: .orange, title: "See the Big Picture",
             text: "Arrange ideas on an infinite canvas, and turn notes into sortable tables with Bases.",
             points: [("rectangle.3.group", "Canvas for brainstorming and maps"), ("tablecells", "Bases filter and sort by properties"), ("calendar", "Daily notes and templates")]),
        Page(id: 4, symbol: "sparkles", color: .green, title: "Always a Shortcut Away",
             text: "Everything is reachable from the keyboard, the share sheet, widgets and Shortcuts.",
             points: shortcutPoints),
    ]

    var body: some View {
        let p = Self.pages[page]
        VStack(spacing: 0) {
            HStack {
                Spacer()
                if page < Self.pages.count - 1 {
                    Button { finish() } label: {
                        Text("Skip").frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .keyboardShortcut(.cancelAction)
                }
            }
            .frame(minHeight: 44)
            .padding(.horizontal)

            ScrollView {
                VStack(spacing: 20) {
                    ZStack {
                        Circle().fill(p.color.opacity(0.15)).frame(width: 120, height: 120)
                        Image(systemName: p.symbol)
                            .font(.system(size: 52, weight: .semibold))
                            .foregroundStyle(p.color)
                            .symbolEffect(.bounce, value: reduceMotion ? 0 : page)
                    }
                    .accessibilityHidden(true)
                    .padding(.top, 8)

                    Text(p.title)
                        .font(.largeTitle.bold())
                        .multilineTextAlignment(.center)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityFocused($titleFocused)
                    Text(p.text)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(Array(p.points.enumerated()), id: \.offset) { _, point in
                            Label { Text(point.1) } icon: {
                                Image(systemName: point.0).foregroundStyle(p.color).frame(width: 28)
                            }
                            .font(.body)
                        }
                    }
                    .padding(.top, 8)
                    .frame(maxWidth: 380, alignment: .leading)
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 16)
                .frame(maxWidth: .infinity)
                .id(page)
                .transition(reduceMotion ? .opacity : .asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                                                  removal: .move(edge: .leading).combined(with: .opacity)))
            }

            pageDots
                .padding(.vertical, 12)

            HStack(spacing: 12) {
                if page > 0 {
                    Button("Back") { go(page - 1) }
                        .controlSize(.large)
                }
                Button {
                    if page == Self.pages.count - 1 { finish() } else { go(page + 1) }
                } label: {
                    Text(page == Self.pages.count - 1 ? "Get Started" : "Continue").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .frame(maxWidth: 320)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        #if os(macOS)
        .frame(width: 560, height: 620)
        #endif
        .gesture(DragGesture(minimumDistance: 30).onEnded { v in
            if v.translation.width < -40, page < Self.pages.count - 1 { go(page + 1) }
            if v.translation.width > 40, page > 0 { go(page - 1) }
        })
        #if os(macOS)
        // Closing the window counts as finishing the tour.
        .onDisappear { Self.markSeen() }
        #endif
        .accessibilityAction(named: "Next page") { if page < Self.pages.count - 1 { go(page + 1) } }
        .accessibilityAction(named: "Previous page") { if page > 0 { go(page - 1) } }
    }

    private var pageDots: some View {
        HStack(spacing: 8) {
            ForEach(Self.pages) { p in
                Circle()
                    .fill(p.id == page ? Color.primary : Color.secondary.opacity(0.6))
                    .frame(width: 8, height: 8)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Page \(page + 1) of \(Self.pages.count)"))
        // Swipe up/down with VoiceOver to change page, like a system page control.
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: if page < Self.pages.count - 1 { go(page + 1) }
            case .decrement: if page > 0 { go(page - 1) }
            @unknown default: break
            }
        }
    }

    private func go(_ p: Int) {
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.35)) { page = p }
        // Announce the new page: move VoiceOver focus to its title.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { titleFocused = true }
    }

    private func finish() {
        Self.markSeen()
        dismiss()
    }

    static func markSeen() {
        UserDefaults.standard.set(true, forKey: "hasSeenOnboarding")
        NetheriteTips.donate(NetheriteTips.onboardingFinished)
    }
}

#Preview { OnboardingView() }
