import SwiftUI

struct HomeView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "waveform.circle")
                .font(.system(size: 64))
                .foregroundStyle(.tint)
            Text("Social Mirror")
                .font(.largeTitle.bold())
            Text("Foundation ready.")
                .foregroundStyle(.secondary)
        }
        .padding()
        .navigationTitle("Home")
    }
}

#Preview {
    NavigationStack { HomeView() }
}
