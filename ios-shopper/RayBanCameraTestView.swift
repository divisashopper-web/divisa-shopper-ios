import SwiftUI

/// Prueba aislada: Ray-Ban Meta -> SDK CameraAccess -> pantalla local.
struct RayBanCameraTestView: View {
    @ObservedObject var manager: MetaWearablesManager
    @State private var isConnecting = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("CÁMARA RAY-BAN")
                    .font(.title2.bold())
                Text("Prueba independiente · sin LiveKit ni videollamada")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                ZStack {
                    Rectangle().fill(.black)
                    if let image = manager.previewImage {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                    } else {
                        VStack(spacing: 12) {
                            Image(systemName: "eyeglasses")
                                .font(.largeTitle)
                            Text("Esperando imagen de las gafas")
                                .font(.subheadline)
                        }
                        .foregroundStyle(.white)
                    }
                }
                .frame(height: 280)
                .clipShape(RoundedRectangle(cornerRadius: 14))

                Button(isConnecting ? "Conectando cámara Meta…" : "Conectar cámara Ray-Ban") {
                    isConnecting = true
                    Task {
                        await manager.startRayBanPreview()
                        isConnecting = false
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isConnecting)

                Button("Detener cámara Ray-Ban") {
                    manager.stopRayBanPreview()
                    isConnecting = false
                }
                .buttonStyle(.bordered)

                Group {
                    Text("Registro Meta: \(manager.registrationStatus)")
                    Text("Gafas registradas: \(manager.detectedGlasses)")
                    Text("Gafas activas elegibles: \(manager.activeGlassesAvailable ? "Sí" : "No")")
                    Text("DeviceSession: \(manager.sdkSessionState)")
                    Text("CameraStream: \(manager.sdkStreamState)")
                    Text("Frames recibidos: \(manager.receivedFrameCount)")
                    Text("Imágenes visibles: \(manager.previewImageCount)")
                    Text("Etapa: \(manager.pipelineStage)")
                    Text("Error Meta: \(manager.lastSDKError)")
                    Text("Diagnóstico: \(manager.diagnostic)")
                    Divider()
                    Text("Último intento #\(manager.attemptNumber): \(manager.lastAttemptResult)")
                    Text("Última etapa: \(manager.lastAttemptStage)")
                    Text("Historial de conexión (no se borra al detener):")
                    ForEach(Array(manager.attemptEvents.enumerated()), id: \.offset) { _, event in
                        Text(event)
                    }
                }
                .font(.footnote.monospaced())
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding()
        }
        .navigationTitle("Ray-Ban Meta")
        .navigationBarTitleDisplayMode(.inline)
    }
}
