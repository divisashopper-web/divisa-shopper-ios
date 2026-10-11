# Auditoría Meta oficial — fase 2: vídeo, audio, pruebas y riesgos

Fecha: 2026-10-11. Investigación de código fuente, NO cambio de código de producción.

## VideoCaptureHandler.swift
- AVAssetWriterInput(mediaType: .video, outputSettings: nil, sourceFormatHint: ...) permite passthrough de HEVC.
- La primera escritura requiere keyframe HEVC (NAL 16–21, IDR/BLA/CRA) para evitar archivos negros.
- Ajusta PTS y DTS para mantener orden creciente y fija duración por defecto 1/24 cuando falta.
- Marca flags sync/dependency; Meta comenta que Photos puede rechazar MOV sin índice correcto de keyframes.
- Mutex alrededor de append y markAsFinished; no escribir después de finalizar.
**Aplicación**: grabadora de gafas separada de la grabadora de iPhone; unir segmentos al finalizar o normalizar formato/tiempo.

## VideoFrameDecoder.swift
- VideoToolbox VTDecompressionSession, reconstrucción si cambia formato, retiene último frame bueno, espera keyframe tras reiniciar.
- Es decodificador de preview, no grabador; para LiveKit se necesita CVPixelBuffer, no UIImage.
**Aplicación**: implementar adaptador de salida CVPixelBuffer y preview desacoplado; no decodificar cada frame dos veces.

## AudioInputHandler.swift + AudioCaptureHandler.swift
- Captura opcional HFP Bluetooth, AVAudioEngine con tap; fuerza preferredInput HFP, nunca micrófono iPhone como sustituto.
- Cambia AVAudioSession a .playAndRecord, mode .videoRecording y activa/desactiva sesión.
- Codifica AAC 44.1 kHz mono, 192 kbps; maneja interrupciones y silencios para alinear timeline.
**Riesgo crítico**: LiveKit ya controla AVAudioSession; copiar este handler puede cortar la llamada, alterar rutas de audio o reproducir crash anterior. No integrarlo hasta diseñar un único propietario de audio y probar en iPhone.

## Tests oficiales
- MockDeviceKit empareja unas Ray-Ban simuladas, inyecta plant.mp4 y verifica sesión, frames y cierre.
- Prueba tap del panel táctil: pausa y reanudación, mantiene último frame en pantalla.
- Prueba segundo plano: termina la sesión sin mostrar falso error.
- Reportes públicos muestran que incluso el ejemplo oficial ha tenido problemas de conexión/MockDeviceKit en ciertas versiones: issue #240 y #197. No atribuir todos los fallos a DIVISA SHOPPER ni asumir que Meta garantiza estabilidad.

## Hallazgo adicional
La ruta oficial de grabación no es la ruta de videollamada. Reutilizar su manejo de cámara y writer no implica que LiveKit pueda consumir HEVC sin decodificación. El diseño debe tener **un solo flujo de recepción** y dos consumidores independientes (grabador HEVC y adaptador de frames LiveKit). Un tercer consumidor de preview debe actualizarse a menor frecuencia.

## Orden propuesto de implementación
1. Añadir pruebas de estados y trazas diagnósticas; no tocar el codec.
2. Añadir observación de errores de sesión, disponibilidad de gafas y watchdog de frames a la ruta actual.
3. Construir pipeline HEVC/decoder/recorder aislado detrás de protocolo, sin cambiar la cámara activa.
4. Probar compatibilidad con LiveKit y fallback iPhone con grabación por segmentos.
5. Evaluar audio HFP con LiveKit por separado, sin asumir compatibilidad.
6. Compilar y ejecutar pruebas CI antes de ofrecer nueva IPA.

## Fuentes
- https://github.com/facebook/meta-wearables-dat-ios/tree/main/samples/CameraAccess
- https://github.com/facebook/meta-wearables-dat-ios/issues/240
- https://github.com/facebook/meta-wearables-dat-ios/issues/197

## Estado
Análisis de VideoCaptureHandler, AudioInputHandler y pruebas oficiales completado. No hay compilación, IPA ni prueba física en esta fase.
