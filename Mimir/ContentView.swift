import SwiftUI

struct ContentView: View {
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 12) {
                Text("Mimir")
                    .font(.system(size: 48, weight: .bold, design: .serif))
                    .foregroundStyle(.white)
                Text("ask, and the head answers")
                    .font(.system(.callout, design: .serif))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(minWidth: 900, minHeight: 600)
    }
}

#Preview {
    ContentView()
}
