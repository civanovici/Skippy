import SwiftUI

struct PlayerView: View {
    @State var viewModel: PlayerViewModel

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Text(viewModel.title)
                    .font(.title2.weight(.semibold))
                Text(viewModel.subtitle)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 16) {
                Button("-15s") { viewModel.seekBack() }
                Button(viewModel.isPlaying ? "Pause" : "Play") { viewModel.togglePlayPause() }
                Button("+30s") { viewModel.seekForward() }
            }
            .buttonStyle(.bordered)

            Spacer()
        }
        .padding(24)
        .navigationTitle("Player")
        .onAppear {
            viewModel.start()
        }
    }
}

#Preview {
    NavigationStack {
        PlayerView(
            viewModel: PlayerViewModel(
                audiobook: Audiobook.mockLibrary.first!,
                chapter: Audiobook.mockLibrary.first?.chapters.first,
                playerService: PlayerService(),
                nowPlayingService: NowPlayingService()
            )
        )
    }
}
