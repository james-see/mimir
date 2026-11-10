import SwiftUI
import MimirCore

struct SettingsView: View {
    @ObservedObject var vm: ConversationViewModel
    @State private var draft = TeacherSettings.load()
    @State private var apiKey = ""
    @State private var models: [String] = []
    @State private var message: String?
    @State private var fetching = false

    var body: some View {
        Form {
            Section("Brain") {
                TextField("API base URL", text: $draft.endpoint)
                HStack {
                    TextField("Model", text: $draft.model)
                    Menu("Installed models") {
                        ForEach(models, id: \.self) { model in
                            Button(model) { draft.model = model }
                        }
                    }.disabled(models.isEmpty)
                    Button(fetching ? "Loading…" : "Refresh") { Task { await fetchModels() } }
                        .disabled(fetching)
                }
                SecureField("API key (optional for local Ollama)", text: $apiKey)
                Text("Stored in macOS Keychain, not in preferences or transcripts.").font(.caption).foregroundStyle(.secondary)
                HStack {
                    Text("Temperature")
                    Slider(value: $draft.temperature, in: 0...2, step: 0.1)
                    Text(draft.temperature, format: .number.precision(.fractionLength(1))).monospacedDigit()
                }
            }
            Section("Teacher") {
                Picker("Voice", selection: $draft.voice) {
                    ForEach(vm.availableVoices.isEmpty ? [draft.voice] : vm.availableVoices, id: \.self) { voice in
                        Text(voiceLabel(voice)).tag(voice)
                    }
                }
                Text("bm: British male · bf: British female · am/af: American male/female").font(.caption).foregroundStyle(.secondary)
                Text("Teacher instructions")
                TextEditor(text: $draft.persona).frame(height: 105).font(.body)
                Button("Restore teacher instructions") { draft.persona = ConversationEngine.defaultPersona }
            }
            Section("Local conversations") {
                Toggle("Save conversations and restore the last session", isOn: $draft.saveConversations)
                HStack {
                    Button("Show saved files") { vm.showSavedFiles() }
                    Button("New conversation") { vm.newConversation() }.disabled(vm.isResponding)
                }
                Text("Turning saving off does not delete existing files. Conversations stay on this Mac; remote model providers receive the current conversation when selected.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let message { Text(message).font(.callout).textSelection(.enabled) }
            HStack {
                Spacer()
                Button("Save settings") {
                    Task {
                        do {
                            try await vm.applySettings(draft, apiKey: apiKey)
                            message = "Saved. Changes apply to the next question."
                        } catch { message = error.localizedDescription }
                    }
                }.disabled(!vm.ready || vm.isResponding).keyboardShortcut(.defaultAction)
            }
        }
        .formStyle(.grouped)
        .frame(width: 640, height: 650)
        .onAppear { apiKey = APIKeyStore.read() ?? "" }
    }

    private func voiceLabel(_ voice: String) -> String {
        let components = voice.split(separator: "_")
        guard components.count >= 2 else { return voice }
        return "\(components.dropFirst().joined(separator: " ").capitalized) (\(components[0]))"
    }

    private func fetchModels() async {
        fetching = true
        defer { fetching = false }
        do {
            let config = try draft.config(apiKey: apiKey)
            var request = URLRequest(url: config.baseURL.appendingPathComponent("models"))
            request.timeoutInterval = 15
            if let key = config.apiKey { request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw URLError(.badServerResponse) }
            struct Model: Decodable { let id: String }
            struct List: Decodable { let data: [Model] }
            models = try JSONDecoder().decode(List.self, from: data).data.map(\.id).sorted()
            message = "Found \(models.count) models."
        } catch { message = "Could not list models: \(error.localizedDescription). You can enter a model name manually." }
    }
}
