import SwiftUI
import LiveKit

/// Muestra la primera cámara remota publicada en la sala.
/// En V1 la sala privada tendrá un cliente y un shopper.
struct RemoteClientVideoView: View {
    @ObservedObject var room: Room

    var body: some View {
        Group {
            if let track = remoteCameraTrack {
                SwiftUIVideoView(track, layoutMode: .fill)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "person.crop.rectangle")
                        .font(.system(size: 44))
                    Text("Esperando video del cliente")
                }
                .foregroundStyle(.white.opacity(0.8))
            }
        }
    }

    private var remoteCameraTrack: VideoTrack? {
        for participant in room.remoteParticipants.values {
            for publication in participant.videoTracks {
                if publication.source == .camera,
                   let track = publication.track as? VideoTrack {
                    return track
                }
            }
        }
        return nil
    }
}
