# Auditoría de integración: núcleo oficial Meta → DIVISA SHOPPER

Estado: fase de análisis; no sustituir la ruta de cámara que ya funcionó físicamente. Rama aislada `meta-official-core-audit`.

## Código oficial revisado (facebook/meta-wearables-dat-ios)
- `samples/CameraAccess/CameraAccess/ViewModels/WearablesViewModel.swift`: registro, devicesStream, compatibilidad de firmware y errores.
- `samples/CameraAccess/CameraAccess/ViewModels/CameraViewModel.swift`: DeviceSession, Camera, Stream, publishers de estado/error, foto, captura y lifecycle.
- `samples/CameraAccess/CameraAccess/Media/VideoRecorder.swift`: escritor MOV sincronizado, comienza en keyframe HEVC, captura audio HFP opcional.
- `samples/CameraAccess/CameraAccess/Media/VideoFrameDecoder.swift`: descompresión HEVC independiente, reinicio ante cambio de formato, espera keyframe.
- `samples/CameraAccess/CameraAccess/Media/AudioCaptureHandler.swift`: audio Bluetooth HFP, AAC y relleno de silencio ante interrupciones.
- `samples/CameraAccess/CameraAccess/CameraAccess.entitlements`: HotspotConfiguration y wifi-info.
- `samples/CameraAccess/CameraAccess/Info.plist`: callback MWDAT, Bluetooth, Bonjour, audio y permisos.
- `samples/CameraAccess/README.md`: Meta cierra el stream al pasar a segundo plano.

## Diferencias verificadas con DIVISA SHOPPER
| Área | Ejemplo Meta | DIVISA SHOPPER actual | Decisión |
| --- | --- | --- | --- |
| Vídeo | hvc1 comprimido; grabación passthrough | raw; reconstrucción CMSampleBuffer | Prototipar adaptador HEVC→CVPixelBuffer para LiveKit, sin cambiar producción aún |
| Preview | VideoFrameDecoder separado | makeUIImage por fotograma | Separar ruta UI y regular frecuencia de preview |
| Sesión | escucha statePublisher y errorPublisher | stateStream y stream errors; sin session errorPublisher | Incorporar errores de sesión |
| Detección | AutoDeviceSelector persistente y devicesStream | selector por intento | Vigilar dispositivo y compatibilidad |
| Grabación | lock, keyframe, writer passthrough | AVAssetWriter raw, resolución fijada por primer frame | Evitar mezcla de fuentes/dimensiones en mismo writer |
| Audio | HFP de gafas en grabación | LiveKit posee audio; grabador sin audio | No copiar captura HFP sin verificar convivencia con LiveKit |
| Permisos | entitlements Wi-Fi | no declarados en project.yml | Validar provisioning y firma antes de incorporar |
| Segundo plano | termina stream | sesión comercial necesita continuidad | Diseñar política explícita y probar restricciones iOS |
| Reconexión | estados y errores diferenciados | fallback iPhone, estados a veces desincronizados | Máquina de estados única y vigilancia de fotogramas |

## Integración prevista
1. **MetaCore** (basado en ciclo de vida oficial): registro, selección de gafas, compatibilidad, sesiones, stream, errores.
2. **MetaVideoPipeline**: una ruta de vídeo comprimido a grabador, otra a decodificador/LiveKit, preview desacoplada.
3. **ShopperCameraCoordinator**: fuente activa única, conmutación al iPhone y recuperación; conservar llamada LiveKit.
4. **RecordingCoordinator**: archivos válidos durante cambios de fuente; sin mezclar tamaños ni tiempos incompatibles.
5. **Pruebas**: mock de dispositivo, transición de estados, falta de fotogramas, interrupción y retorno; compilación y firma antes de IPA.

## Condiciones de aceptación
- Ray-Ban real entrega fotogramas a LiveKit sin afectar audio.
- Grabación MOV se puede abrir y compartir.
- Si Ray-Ban pierde vídeo, iPhone sigue transmitiendo y la grabación se finaliza de forma segura.
- Reconexión Ray-Ban no termina llamada ni deja selector de cámara incorrecto.
- Sin cambios en Floot/web ni instalaciones físicas hasta superar compilación y pruebas.

## Riesgos por resolver antes de migrar
- Codec HEVC comprimido no entra directamente al puente LiveKit que requiere CVPixelBuffer.
- La captura HFP de Meta podría competir con la sesión de audio LiveKit.
- Los entitlements Wi-Fi dependen del perfil de aprovisionamiento de Apple.
- El ejemplo de Meta no promete streaming en segundo plano ni grabación continua de dos horas.
- Conservar la ruta raw operativa como reversión; no asumir que el ejemplo garantiza estabilidad física.
