import SwiftUI

struct ShopperSessionView: View {
    @EnvironmentObject var session: ShopperSessionModel
    @State private var showEndSessionConfirmation = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                header
                clientStage
                sourcePicker
                backupCameraIndicator
                rayBanRecoveryControl
                cameraSwitchIndicator
                recordingIndicator
                controls
                recordingResult
                status
                if session.isEndingSession {
                    ProgressView("Guardando y cerrando sesión…")
                        .font(.footnote.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Spacer()
            }
            .padding()
            .navigationBarTitleDisplayMode(.inline)
            .alert("Revisar grabación", isPresented: Binding(
                get: { session.recordingSaveError != nil },
                set: { if !$0 { session.recordingSaveError = nil } }
            )) {
                Button("Entendido") { session.recordingSaveError = nil }
            } message: {
                Text(session.recordingSaveError ?? "")
            }
        }
    }

    private var header: some View {
        VStack(spacing: 4) {
            Text("DIVISA SHOPPER")
                .font(.title.bold())
            Text("APP DEL SHOPPER")
                .font(.caption.weight(.semibold))
            HStack(spacing: 7) {
                Image(systemName: connectionIcon)
                Text(session.connectionState.rawValue)
            }
            .font(.subheadline.weight(.semibold))
            .accessibilityLabel("Estado de sesión: \(session.connectionState.rawValue)")
            NavigationLink {
                RecordingsLibraryView(recorder: session.localRecorder)
            } label: {
                Label("Grabaciones", systemImage: "video.badge.checkmark")
                    .font(.caption.weight(.semibold))
            }
        }
    }

    private var connectionIcon: String {
        switch session.connectionState {
        case .idle: return "circle"
        case .connecting, .reconnecting: return "arrow.triangle.2.circlepath"
        case .connected: return "checkmark.circle.fill"
        case .disconnected: return "wifi.slash"
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
            .disabled(session.connectionState == .connecting || session.connectionState == .reconnecting || session.isEndingSession || session.isSwitchingCamera)
            .onChange(of: session.selectedCamera) { _, newValue in
                session.selectCamera(newValue)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }


    @ViewBuilder
    private var backupCameraIndicator: some View {
        if session.isUsingBackupCamera {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                VStack(alignment: .leading, spacing: 2) {
                    Text("CÁMARA DE RESPALDO ACTIVA").fontWeight(.bold)
                    Text("Ray-Ban desconectada · usando iPhone trasera").font(.caption)
                }
                Spacer()
            }
            .font(.subheadline)
            .padding(10)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    @ViewBuilder
    private var rayBanRecoveryControl: some View {
        if session.isUsingBackupCamera && session.preferredCamera == .rayBanMeta {
            Button {
                session.retryPreferredCamera()
            } label: {
                Label("Volver a intentar Ray-Ban", systemImage: "eyeglasses")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(session.connectionState != .connected || session.isEndingSession)
        }
    }

    @ViewBuilder
    private var cameraSwitchIndicator: some View {
        if session.isSwitchingCamera {
            HStack(spacing: 8) {
                ProgressView()
                Text("Cambiando cámara…")
                    .fontWeight(.semibold)
                Spacer()
            }
            .font(.subheadline)
            .padding(10)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    @ViewBuilder
    private var recordingIndicator: some View {
        if session.isRecording {
            HStack(spacing: 8) {
                Image(systemName: "record.circle.fill")
                Text("GRABANDO")
                    .fontWeight(.bold)
                Spacer()
                Text(session.recordingTimeText)
                    .monospacedDigit()
                    .fontWeight(.semibold)
            }
            .font(.subheadline)
            .padding(10)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
            .accessibilityLabel("Grabación activa, \(session.recordingTimeText)")
        }
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Button(session.isMuted ? "Activar audio" : "Silenciar") {
                session.toggleMute()
            }
            .buttonStyle(.bordered)
            .disabled(session.connectionState != .connected || session.isEndingSession || session.isSwitchingCamera)

            Button(session.isRecording ? "Detener grabación" : "Grabar") {
                session.toggleRecording()
            }
            .buttonStyle(.bordered)
            .disabled(session.connectionState != .connected || session.isEndingSession || session.isSwitchingCamera)

            Button(session.connectionState == .connected ? "Finalizar sesión" : "Iniciar sesión") {
                if session.connectionState == .connected {
                    showEndSessionConfirmation = true
                } else {
                    session.startSession()
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(session.connectionState == .connecting || session.connectionState == .reconnecting || session.isEndingSession || session.isSwitchingCamera)
            .confirmationDialog(
                "¿Finalizar la sesión de compra?",
                isPresented: $showEndSessionConfirmation,
                titleVisibility: .visible
            ) {
                Button("Finalizar sesión", role: .destructive) {
                    session.endSession()
                }
                Button("Continuar comprando", role: .cancel) {}
            } message: {
                Text("La videollamada terminará y, si hay una grabación activa, se guardará antes de cerrar.")
            }
        }
        .font(.caption)
    }


    @ViewBuilder
    private var recordingResult: some View {
        if let url = session.localRecorder.lastRecordingURL,
           let name = session.localRecorder.lastRecordingName {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Última grabación")
                        .font(.caption.weight(.semibold))
                    Text(name)
                        .font(.caption2)
                        .lineLimit(1)
                }
                Spacer()
                ShareLink(item: url) {
                    Label("Compartir", systemImage: "square.and.arrow.up")
                }
                .font(.caption)
            }
            .padding(10)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private var status: some View {
        Text(session.statusMessage)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
