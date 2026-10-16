import SwiftUI

struct ShopperSessionView: View {
    @EnvironmentObject var session: ShopperSessionModel
    @State private var showEndSessionConfirmation = false

    var body: some View {
        NavigationStack {
            ScrollView {
              VStack(spacing: 18) {
                header
                activeCameraBadge
                sessionSafetySummary
                shopperCameraStage
                NavigationLink {
                    RayBanCameraTestView(manager: session.metaWearables)
                } label: {
                    Label("Abrir cámara Ray-Ban · prueba independiente", systemImage: "eyeglasses")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(12)
                }
                .buttonStyle(.borderedProminent)
                clientStage
                Text("Video del cliente")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                sourcePicker
                rayBanFloatingControl
                backupCameraIndicator
                rayBanRecoveryControl
                cameraSwitchIndicator
                recordingIndicator
                controls
                recordingResult
                if session.selectedCamera == .rayBanMeta || session.preferredCamera == .rayBanMeta {
                    Text("Etapa Meta: \(session.metaWearables.pipelineStage)")
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("Frames Meta: \(session.metaWearables.receivedFrameCount)")
                        .font(.caption2.monospaced())
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("Con imagen: \(session.metaWearables.framesWithImageBuffer) · Sin imagen: \(session.metaWearables.framesWithoutImageBuffer)")
                        .font(.caption2.monospaced())
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("Cortes detectados: \(session.metaWearables.streamFreezeCount)")
                        .font(.caption2.monospaced())
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("Diagnóstico Meta: \(session.metaWearables.diagnostic)")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                status
                if session.isEndingSession {
                    ProgressView("Guardando y cerrando sesión…")
                        .font(.footnote.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
              }
              .padding()
            }
            .scrollIndicators(.visible)
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

    private var activeCameraBadge: some View {
        HStack(spacing: 8) {
            Image(systemName: session.selectedCamera == .rayBanMeta ? "eyeglasses" : "camera.fill")
            Text("Cámara activa: \(session.selectedCamera.rawValue)")
                .fontWeight(.semibold)
            Spacer()
        }
        .font(.subheadline)
        .padding(10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityLabel("Cámara activa: \(session.selectedCamera.rawValue)")
    }

    private var sessionSafetySummary: some View {
        HStack(spacing: 12) {
            Label(session.connectionState == .connected ? "En línea" : "No conectada", systemImage: session.connectionState == .connected ? "wifi" : "wifi.slash")
            Spacer()
            Label(session.isRecording ? session.recordingTimeText : "Sin grabar", systemImage: session.isRecording ? "record.circle.fill" : "record.circle")
            Spacer()
            Label(session.isMuted ? "Audio silenciado" : "Audio activo", systemImage: session.isMuted ? "mic.slash.fill" : "mic.fill")
        }
        .font(.caption.weight(.semibold))
        .padding(10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var shopperCameraStage: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18)
                .fill(.black)
                .aspectRatio(16/9, contentMode: .fit)

            if session.isCameraRecoveryWaiting {
                VStack(spacing: 10) {
                    Text("DIVISA SHOPPER")
                        .font(.title2.bold())
                    Text("Estamos cambiando de cámara")
                        .font(.subheadline.weight(.semibold))
                    Text("La sesión y el audio continúan")
                        .font(.caption)
                }
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
                .padding()
            } else if session.selectedCamera == .rayBanMeta,
                      let image = session.rayBanPreviewImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 18))
            } else if session.selectedCamera == .rayBanMeta {
                VStack(spacing: 8) {
                    Image(systemName: "eyeglasses")
                        .font(.title)
                    Text("Esperando imagen real de Ray-Ban…")
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(.white.opacity(0.85))
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "camera.fill")
                        .font(.title)
                    Text("Monitor del shopper")
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(.white.opacity(0.85))
            }
        }
        .overlay(alignment: .topLeading) {
            Text(session.selectedCamera == .rayBanMeta && session.rayBanFramesReady ? "RAY-BAN · VIDEO REAL" : "CÁMARA DEL SHOPPER")
                .font(.caption2.weight(.bold))
                .padding(7)
                .background(.black.opacity(0.65), in: Capsule())
                .foregroundStyle(.white)
                .padding(8)
        }
    }

    /// Prueba aislada: Meta -> imagen en el iPhone, sin publicar LiveKit ni grabar.
    /// Úsese antes de consumir una instalación para probar videollamada completa.
    private var rayBanLocalPreviewTest: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PRUEBA 1 · IMAGEN DE LAS GAFAS")
                .font(.caption.weight(.bold))
            Button("Registrar gafas con Meta") {
                Task { await session.metaWearables.registerGlasses() }
            }
            .buttonStyle(.bordered)
            Text("Registro SDK Meta: \(session.metaWearables.registrationStatus)")
                .font(.caption2.monospaced())
                .textSelection(.enabled)
            Text("Gafas detectadas por SDK: \(session.metaWearables.detectedGlasses)")
            Text("Estado real DeviceSession: \(session.metaWearables.sdkSessionState)")
            Text("Estado real CameraStream: \(session.metaWearables.sdkStreamState)")
            Text("Último error SDK: \(session.metaWearables.lastSDKError)")
                .font(.caption2.monospacedDigit())
            if session.metaWearables.detectedGlasses == 0 {
                Text("Meta todavía no informa gafas disponibles para esta aplicación.")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
            Button("Probar imagen Ray-Ban en este iPhone") {
                Task { await session.metaWearables.startRayBanPreview() }
            }
            .buttonStyle(.bordered)
            .disabled(session.isSwitchingCamera || session.isEndingSession ||
                      session.connectionState == .connected)
            Button("Detener prueba de cámara Ray-Ban") {
                session.metaWearables.stopRayBanPreview()
            }
            .buttonStyle(.bordered)
            .disabled(session.isSwitchingCamera || session.isEndingSession ||
                      session.connectionState == .connected)
            if let image = session.metaWearables.previewImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 220, maxHeight: 360)
                    .background(.black)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .accessibilityLabel("Imagen local recibida directamente de Ray-Ban")
            } else {
                Text("Sin imagen todavía · revisa el diagnóstico Meta")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text("Imágenes visibles: \(session.metaWearables.previewImageCount) · Vista alternativa: \(session.metaWearables.previewFallbackCount) · Con pixel buffer: \(session.metaWearables.framesWithImageBuffer) · Recibidos: \(session.metaWearables.receivedFrameCount)")
                .font(.caption2.monospacedDigit())
            Text(session.metaWearables.pipelineStage)
                .font(.caption2.weight(.semibold))
            if session.metaWearables.previewImageCount > 0 &&
                session.metaWearables.framesWithImageBuffer == 0 {
                Text("Meta muestra imagen, pero todavía no hay pixel buffer válido para LiveKit/MOV.")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            } else if session.metaWearables.framesWithImageBuffer > 0 &&
                        session.metaWearables.previewImageCount == 0 {
                Text("Llegan muestras de imagen válidas, pero fallaron ambas conversiones para la vista previa.")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
            if let firstFrameTimeout = session.metaWearables.firstFrameTimeoutDiagnostic {
                if session.metaWearables.previewImageCount > 0 {
                    Text("PRIMER FRAME RECUPERADO · La imagen llegó después de la espera inicial.")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.green)
                } else {
                    Text("ALERTA PRIMER FRAME: \(firstFrameTimeout)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.orange)
                        .textSelection(.enabled)
                }
            }
            Text(session.metaWearables.diagnostic)
                .font(.caption2)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var clientStage: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24)
                .fill(.black)
                .aspectRatio(9/16, contentMode: .fit)
            RemoteClientVideoView(room: session.liveKit.room)
                .clipShape(RoundedRectangle(cornerRadius: 24))
            if session.connectionState != .connected || !session.clientVideoAvailable {
                VStack(spacing: 10) {
                    Image(systemName: "person.crop.rectangle")
                        .font(.largeTitle)
                    Text(session.connectionState == .connecting ? "Conectando con el cliente…" : session.connectionState == .connected ? "Cliente conectado · esperando su cámara" : "Esperando video del cliente")
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(.white.opacity(0.85))
                .padding()
            }
        }
    }

    /// Indicador basado en fotogramas recientes, no solo en Bluetooth.
    private var rayBanVideoReady: Bool {
        guard session.metaWearables.isStreaming,
              session.metaWearables.hasReceivedFrame,
              session.metaWearables.framesWithImageBuffer > 0,
              let lastFrame = session.metaWearables.lastFrameReceivedAt else { return false }
        return Date().timeIntervalSince(lastFrame) < 3
    }

    private var rayBanFloatingControl: some View {
        HStack {
            Spacer()
            Button {
                if session.selectedCamera == .rayBanMeta {
                    session.selectCamera(.iPhoneBack)
                } else if rayBanVideoReady {
                    session.selectCamera(.rayBanMeta)
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "eyeglasses")
                    Text(session.selectedCamera == .rayBanMeta ? "Volver al iPhone" : rayBanVideoReady ? "Usar Ray-Ban" : "Ray-Ban esperando video")
                        .font(.caption.weight(.semibold))
                    Circle()
                        .fill(rayBanVideoReady ? Color.green : Color.gray)
                        .frame(width: 10, height: 10)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(.regularMaterial, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(session.connectionState != .connected || session.isSwitchingCamera || session.isEndingSession || (session.selectedCamera != .rayBanMeta && !rayBanVideoReady))
            .accessibilityLabel(rayBanVideoReady ? "Ray-Ban con imagen disponible" : "Ray-Ban sin imagen confirmada")
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
            .accessibilityHint(session.connectionState == .connected ? "Finaliza la compra actual" : "Conecta la aplicación con la sesión privada del cliente")
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
        if session.isSwitchingCamera || session.isCameraRecoveryWaiting {
            HStack(spacing: 8) {
                ProgressView()
                Text(session.isCameraRecoveryWaiting ? "Estamos cambiando de cámara · audio activo" : "Cambiando cámara…")
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
            // A recording is local and independent from LiveKit. If the call
            // drops while recording, the shopper must still be able to stop
            // and finalize the file safely.
            .disabled((!session.isRecording && session.connectionState != .connected) || session.isEndingSession || session.isSwitchingCamera)

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
