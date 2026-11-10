import SwiftUI

@main
struct MimirApp: App {
    @StateObject private var vm = ConversationViewModel()
    var body: some Scene {
        WindowGroup {
            ContentView(vm: vm)
        }
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(after: .newItem) {
                Button("New Conversation") { vm.newConversation() }
                    .keyboardShortcut("n", modifiers: .command)
                    .disabled(vm.isResponding)
            }
        }
        Settings {
            SettingsView(vm: vm)
        }
    }
}
