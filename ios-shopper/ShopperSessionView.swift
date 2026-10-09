import SwiftUI

struct ShopperSessionView: View {
    @EnvironmentObject var session: ShopperSessionModel

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                header
                clientStage
                sourcePicker
                controls
                status
                Spacer()
            }
            .padding()
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var header: some View {
        VStack(spacing: 4) {
            Text("DIVISA SHOPPER")
                .font(.title.bold())
            Text("APP DEL SHOPPER")
                .font(.caption.weight(.semibold))
            Text(session.connectionState.rawValue)
                .font(.subheadline)
        }
    }

    private var clientStage: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24)
                .fill(.black)
                .aspectRatio(9/16, contentMode: .fit)
            RemoteClientVideoView(room: session.liveKit.room)
                .clipShape(RoundedRectangle(cornerRadius: 24))
        }
    }

    private var sourcePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Cámara del Shopper")
                .font(.headline)
            Picker("Fuente de cámara", selection: $session.selectedCamera) {
                ForEach(CameraSource.allCases) { source in
                    Text(source.rawValue).tag(source)
                }
            }
            .pickerStyle(.menu)
            .onChange(of: session.selectedCamera) { _, newValue in
                session.selectCamera(newValue)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Button(session.isMuted ? "Activar audio" : "Silenciar") {
                session.toggleMute()
            }
            .buttonStyle(.bordered)

            Button(session.isRecording ? "Detener grabación" : "Grabar") {
                session.toggleRecording()
            }
            .buttonStyle(.bordered)

            Button("Iniciar sesión") {
                session.startSession()
            }
            .buttonStyle(.borderedProminent)
        }
        .font(.caption)
    }

    private var status: some View {
        Text(session.statusMessage)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
