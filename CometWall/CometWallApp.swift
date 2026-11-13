import SwiftUI
import WebKit

enum Layout: String { case wall, sidebar }

@main
struct CometWallApp: App {
    @StateObject private var store = PaneStore()
    @AppStorage("layout") private var layout: Layout = .wall

    var body: some Scene {
        WindowGroup {
            ContentView(layout: $layout)
                .environmentObject(store)
                .frame(minWidth: 900, minHeight: 600)
        }
        .commands {
            CommandMenu("Layout") {
                Button("Wall") { layout = .wall }.keyboardShortcut("1")
                Button("Sidebar") { layout = .sidebar }.keyboardShortcut("2")
                Divider()
                Button("Edit Panes…") { NSWorkspace.shared.open(PaneStore.configURL) }
                    .keyboardShortcut(",", modifiers: [.command, .shift])
                Button("Reload Pane List") { store.reload() }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                Button("Unlock Saved Logins") { store.unlockSavedLogins() }
            }
        }
    }
}

/// One tile area serves both layouts. Web views never move between parent views:
/// WebKit stops drawing a page with live video (the KVM stream) once its view is
/// re-parented, which showed up as a blank pane on expand. So the tiles stay
/// mounted in one place and only their frames change.
struct ContentView: View {
    @EnvironmentObject var store: PaneStore
    @Binding var layout: Layout
    @State private var expanded: String?
    @AppStorage("selectedPane") private var selected: String = ""

    /// The pane shown full size, if any: the expanded tile on the wall, the
    /// selected row in the sidebar.
    private var focusedName: String? {
        switch layout {
        case .wall: return expanded
        case .sidebar: return store.panes.contains { $0.name == selected } ? selected : store.panes.first?.name
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            if layout == .sidebar {
                List(store.panes, selection: $selected) { pane in
                    Text(pane.name).tag(pane.name)
                }
                .frame(width: 200)
                Divider()
            }
            TileArea(focused: focusedName, showExpand: layout == .wall) { name in
                expanded = (expanded == name) ? nil : name
            }
        }
        .onExitCommand { expanded = nil }
        .toolbar {
            Picker("Layout", selection: $layout) {
                Image(systemName: "square.grid.2x2").tag(Layout.wall)
                Image(systemName: "sidebar.left").tag(Layout.sidebar)
            }
            .pickerStyle(.segmented)
            .help("Wall (⌘1) or sidebar (⌘2)")
        }
    }
}

struct TileArea: View {
    @EnvironmentObject var store: PaneStore
    let focused: String?
    let showExpand: Bool
    let toggle: (String) -> Void

    var body: some View {
        WallLayout(focusedIndex: store.panes.firstIndex { $0.name == focused }) {
            ForEach(store.panes) { pane in
                Tile(pane: pane, expanded: focused == pane.name, showExpand: showExpand) { toggle(pane.name) }
                    .opacity(focused == nil || focused == pane.name ? 1 : 0)
                    .allowsHitTesting(focused == nil || focused == pane.name)
            }
        }
        .padding(focused == nil ? 8 : 0)
    }
}

/// Grid of tiles, or one tile filling the area with the rest shrunk to nothing.
struct WallLayout: SwiftUI.Layout {
    var focusedIndex: Int?
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        if let f = focusedIndex, subviews.indices.contains(f) {
            for (i, view) in subviews.enumerated() {
                let size = i == f ? bounds.size : CGSize(width: 1, height: 1)
                view.place(at: bounds.origin, proposal: ProposedViewSize(size))
            }
            return
        }
        let count = max(subviews.count, 1)
        // 1-2 side by side, 3-4 as 2x2, 5-6 as 3x2; never narrower than ~420pt.
        let cols = min(Int(ceil(sqrt(Double(count)))), max(1, Int(bounds.width / 420)))
        let rows = Int(ceil(Double(count) / Double(cols)))
        let w = (bounds.width - CGFloat(cols - 1) * spacing) / CGFloat(cols)
        let h = (bounds.height - CGFloat(rows - 1) * spacing) / CGFloat(rows)
        for (i, view) in subviews.enumerated() {
            let x = bounds.minX + CGFloat(i % cols) * (w + spacing)
            let y = bounds.minY + CGFloat(i / cols) * (h + spacing)
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(width: w, height: h))
        }
    }
}

struct Tile: View {
    @EnvironmentObject var store: PaneStore
    let pane: PaneConfig
    let expanded: Bool
    let showExpand: Bool
    let toggle: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text(pane.name).font(.headline).lineLimit(1)
                Spacer()
                LoginButton(pane: pane)
                Button { store.goHome(pane) } label: { Image(systemName: "house") }.help("Back to start page")
                Button { store.refresh(pane) } label: { Image(systemName: "arrow.clockwise") }.help("Reload")
                if showExpand {
                    Button(action: toggle) {
                        Image(systemName: expanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                    }
                    .help(expanded ? "Back to wall (Esc)" : "Expand")
                }
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.bar)
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { if showExpand { toggle() } }

            if store.loginFailed.contains(pane.name) {
                HStack {
                    Image(systemName: "key.slash")
                    Text("Auto-login didn't work. Check the saved password.")
                    Spacer()
                    Button("Try again") { store.retryLogin(pane) }
                }
                .font(.callout)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(.yellow.opacity(0.25))
            }
            WebPane(webView: store.webView(for: pane))
                .overlay {
                    if let error = store.errors[pane.name] {
                        VStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle").font(.title)
                            Text(error.message).multilineTextAlignment(.center)
                            HStack {
                                if let host = error.untrustedHost {
                                    Button("Trust this certificate") { store.trust(host: host, for: pane) }
                                        .help("Always accept the certificate \(host) presents")
                                }
                                Button("Retry") { store.goHome(pane) }
                            }
                        }
                        .padding()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(.background)
                    }
                }
        }
        .clipShape(RoundedRectangle(cornerRadius: expanded ? 0 : 8))
        .overlay(RoundedRectangle(cornerRadius: expanded ? 0 : 8).stroke(.separator))
    }
}

/// Hosts a pane's WKWebView. Each pane has exactly one host for the life of the
/// window (see ContentView), so the web view is attached once and never moved.
struct WebPane: NSViewRepresentable {
    let webView: WKWebView

    func makeNSView(context: Context) -> WKWebView {
        webView.removeFromSuperview()
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {}
}

/// Key button on a tile: save, replace or forget this pane's password.
struct LoginButton: View {
    @EnvironmentObject var store: PaneStore
    let pane: PaneConfig
    @State private var open = false
    @State private var password = ""
    @State private var error: String?

    private var saved: Bool { pane.url.host.map(store.savedLoginHosts.contains) ?? false }

    var body: some View {
        Button { open.toggle() } label: { Image(systemName: saved ? "key.fill" : "key") }
            .help(saved ? "Auto-login is on" : "Save a login for auto-login")
            .popover(isPresented: $open, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Login for \(pane.url.host ?? pane.name)").font(.headline)
                    Text("Stored in your Keychain. CometWall asks for Touch ID before using it.")
                        .font(.caption).foregroundStyle(.secondary)
                    SecureField(saved ? "New password" : "Password", text: $password)
                        .onSubmit(save)
                    if let error { Text(error).font(.caption).foregroundStyle(.red) }
                    HStack {
                        if saved {
                            Button("Forget", role: .destructive) {
                                store.forgetLogin(for: pane)
                                open = false
                            }
                        }
                        Spacer()
                        Button("Save", action: save).keyboardShortcut(.defaultAction).disabled(password.isEmpty)
                    }
                }
                .padding()
                .frame(width: 300)
            }
    }

    private func save() {
        guard !password.isEmpty else { return }
        do {
            try store.saveLogin(password, for: pane)
            password = ""
            error = nil
            open = false
        } catch {
            self.error = error.localizedDescription
        }
    }
}
