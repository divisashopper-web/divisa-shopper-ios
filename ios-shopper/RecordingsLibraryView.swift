import AVKit
import SwiftUI

struct RecordingsLibraryView: View {
    @ObservedObject var recorder: LocalVideoRecorder
    @State private var selectedRecording: URL?

    var body: some View {
        List {
            if recorder.recordings.isEmpty {
                ContentUnavailableView(
                    "Sin grabaciones",
                    systemImage: "video",
                    description: Text("Las sesiones terminadas aparecerán aquí.")
                )
            } else {
                ForEach(recorder.recordings, id: \.self) { url in
                    Button {
                        selectedRecording = url
                    } label: {
                        HStack {
                            Image(systemName: "play.rectangle.fill")
                                .font(.title2)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(url.deletingPathExtension().lastPathComponent)
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(1)
                                Text(fileSizeText(url))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            ShareLink(item: url) {
                                Image(systemName: "square.and.arrow.up")
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .buttonStyle(.plain)
                    .swipeActions {
                        Button(role: .destructive) {
                            try? recorder.deleteRecording(at: url)
                        } label: {
                            Label("Eliminar", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .navigationTitle("Grabaciones")
        .onAppear { recorder.refreshRecordings() }
        .sheet(item: $selectedRecording) { url in
            VideoPlayer(player: AVPlayer(url: url))
                .ignoresSafeArea()
        }
    }

    private func fileSizeText(_ url: URL) -> String {
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else {
            return "Video local"
        }
        return ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }
}

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}
