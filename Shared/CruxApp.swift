import SwiftUI
import SwiftData

@main
struct CruxApp: App {
    let modelContainer: ModelContainer
    @State private var appState = AppState()

    init() {
        do {
            modelContainer = try ModelContainer(for: StoredBook.self)
        } catch {
            fatalError("Failed to initialize SwiftData: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
        }
        .modelContainer(modelContainer)
        #if os(macOS)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open EPUB...") {
                    appState.showOpenPanel = true
                }
                .keyboardShortcut("o", modifiers: .command)
            }
        }
        #endif

        #if os(macOS)
        Settings {
            SettingsView()
        }
        #endif
    }
}

@Observable
final class AppState {
    var showOpenPanel = false
    var selectedBookId: UUID?
}

#if os(macOS)
struct SettingsView: View {
    var body: some View {
        Form {
            Text("Settings will go here")
        }
        .padding()
        .frame(width: 400, height: 200)
    }
}
#endif
