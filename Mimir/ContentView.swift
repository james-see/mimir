import MimirCore
import SwiftUI

struct ContentView: View {
    @StateObject private var vm = ConversationViewModel()

    var body: some View {
        HStack(spacing: 0) {
            avatarPane
            Divider()
            conversationPane
        }
        .frame(minWidth: 900, minHeight: 600)
        .background(Color(white: 0.05))
        .preferredColorScheme(.dark)
    }

    // MARK: - Left: the head

    private var avatarPane: some View {
        ZStack(alignment: .bottom) {
            AvatarView(avatar: vm.avatar)
            statePill
                .padding(.bottom, 20)
        }
        .frame(minWidth: 430)
        .background(
            LinearGradient(
                colors: [Color(white: 0.03), Color(red: 0.05, green: 0.06, blue: 0.1)],
                startPoint: .top, endPoint: .bottom
            )
        )
    }

    private var statePill: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(pillColor)
                .frame(width: 8, height: 8)
            Text(pillText)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.85))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(.black.opacity(0.55), in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.12)))
    }

    private var pillColor: Color {
        switch vm.state {
        case .idle: .gray
        case .listening: .green
        case .thinking: .init(red: 0.95, green: 0.7, blue: 0.2)
        case .speaking: .init(red: 0.35, green: 0.65, blue: 1)
        }
    }

    private var pillText: String {
        switch vm.state {
        case .idle: vm.ready ? "Mimir" : "Waking up…"
        case .listening: "Listening"
        case .thinking: "Thinking"
        case .speaking: "Speaking"
        }
    }

    // MARK: - Right: transcript + input

    private var conversationPane: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(vm.turns) { turn in
                            bubble(for: turn)
                                .id(turn.id)
                        }
                        if !vm.streamingAssistant.isEmpty {
                            bubble(text: vm.streamingAssistant, isUser: false, isStreaming: true)
                                .id("streaming")
                        }
                    }
                    .padding(16)
                }
                .onChange(of: vm.turns.count) { _, _ in scrollToEnd(proxy) }
                .onChange(of: vm.streamingAssistant) { _, _ in scrollToEnd(proxy) }
            }

            if let note = vm.voiceNote ?? vm.errorMessage {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(vm.errorMessage != nil ? .orange : .secondary)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider().padding(.top, 8)
            inputBar
        }
        .frame(minWidth: 400)
    }

    private func scrollToEnd(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.15)) {
            if vm.streamingAssistant.isEmpty, let last = vm.turns.last {
                proxy.scrollTo(last.id, anchor: .bottom)
            } else {
                proxy.scrollTo("streaming", anchor: .bottom)
            }
        }
    }

    private func bubble(for turn: ConversationViewModel.Turn) -> some View {
        bubble(text: turn.text, isUser: turn.role == .user, isStreaming: false)
    }

    private func bubble(text: String, isUser: Bool, isStreaming: Bool) -> some View {
        HStack {
            if isUser { Spacer(minLength: 40) }
            Text(text)
                .font(.system(size: 13.5))
                .foregroundStyle(isUser ? .white : .white.opacity(isStreaming ? 0.65 : 0.92))
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(
                    isUser
                        ? Color(red: 0.25, green: 0.4, blue: 0.75)
                        : Color(white: 0.14),
                    in: RoundedRectangle(cornerRadius: 14)
                )
            if !isUser { Spacer(minLength: 40) }
        }
    }

    private var inputBar: some View {
        HStack(spacing: 10) {
            Button(action: vm.toggleMic) {
                Image(systemName: vm.micEnabled ? "mic.fill" : "mic")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(vm.micEnabled ? .green : .secondary)
                    .frame(width: 34, height: 34)
                    .background(Color(white: 0.12), in: Circle())
            }
            .buttonStyle(.plain)
            .help(vm.micEnabled ? "Stop listening" : "Talk out loud (hands-free)")

            TextField("Ask Mimir…", text: $vm.draftInput)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color(white: 0.12), in: RoundedRectangle(cornerRadius: 10))
                .onSubmit { vm.send() }
                .disabled(!vm.ready)

            Button(action: vm.send) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(
                        vm.ready && !vm.draftInput.isEmpty
                            ? Color(red: 0.25, green: 0.4, blue: 0.75)
                            : Color(white: 0.2),
                        in: Circle()
                    )
            }
            .buttonStyle(.plain)
            .disabled(!vm.ready || vm.draftInput.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(12)
    }
}

#Preview {
    ContentView()
}
