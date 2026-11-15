import SwiftUI

/// The pages of the main window, in sidebar order.
enum HubSection: String, CaseIterable, Identifiable {
    case home
    case dictionary
    case rules
    case signature

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "Home"
        case .dictionary: return "Dictionary"
        case .rules: return "AI Rules"
        case .signature: return "Signature"
        }
    }

    var symbolName: String {
        switch self {
        case .home: return "house"
        case .dictionary: return "character.book.closed"
        case .rules: return "list.bullet.rectangle"
        case .signature: return "signature"
        }
    }
}

/// What the main window currently shows. Owned by the window controller so the menu bar
/// and the Dock icon can open a specific page or the settings.
@MainActor
final class HubNavigation: ObservableObject {
    @Published var section: HubSection = .home
    @Published var isSettingsPresented = false
}

/// Main window: pages in a sidebar, settings at the bottom of it.
struct HubView: View {
    @ObservedObject var coordinator: DictationCoordinator
    @ObservedObject var navigation: HubNavigation

    var body: some View {
        NavigationSplitView {
            List(HubSection.allCases, selection: sectionSelection) { section in
                Label(section.title, systemImage: section.symbolName)
                    .tag(section)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 260)
            .safeAreaInset(edge: .bottom) {
                sidebarFooter
            }
        } detail: {
            page
                .formStyle(.grouped)
                .navigationTitle(navigation.section.title)
        }
        .frame(minWidth: 760, minHeight: 520)
        .sheet(isPresented: $navigation.isSettingsPresented) {
            SettingsSheet(coordinator: coordinator)
        }
        .onAppear {
            coordinator.refreshInputDevices()
        }
    }

    /// `List` selection is optional; the hub always has a page.
    private var sectionSelection: Binding<HubSection?> {
        Binding(
            get: { navigation.section },
            set: { navigation.section = $0 ?? navigation.section }
        )
    }

    @ViewBuilder
    private var page: some View {
        switch navigation.section {
        case .home:
            HomePage(coordinator: coordinator)
        case .dictionary:
            DictionaryPage(coordinator: coordinator)
        case .rules:
            RulesPage(coordinator: coordinator)
        case .signature:
            SignaturePage(coordinator: coordinator)
        }
    }

    private var sidebarFooter: some View {
        VStack(alignment: .leading, spacing: 2) {
            Divider()
                .padding(.bottom, 6)
            Button {
                navigation.isSettingsPresented = true
            } label: {
                Label("Settings", systemImage: "gearshape")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)

            HStack(spacing: 6) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 7, height: 7)
                Text(coordinator.statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 10)
    }

    private var statusColor: Color {
        switch coordinator.phase {
        case .idle: return .green
        case .recording: return .red
        case .transcribing, .pasting: return .orange
        case .failed: return .red
        }
    }
}
