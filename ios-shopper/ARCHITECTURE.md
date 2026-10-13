# Arquitectura V1

## Regla principal
La sesión de compra vive en la app del iPhone. Las Ray-Ban Meta son una fuente de cámara, no el dueño de la sesión.

## Flujo
1. La app solicita un token al backend Render.
2. El iPhone entra a la sala privada de LiveKit.
3. Publica una fuente de video seleccionable.
4. Recibe video/audio del cliente y lo muestra en la pantalla principal.
5. Si Ray-Ban deja de estar disponible, la app mantiene la sala y permite pasar a cámara trasera/frontal del iPhone.
6. Al recuperar o cambiar las gafas, se sustituye la fuente de video sin terminar la sesión.

## Grabación
La grabación local debe quedar desacoplada del estado de LiveKit. Una interrupción temporal de internet no debe destruir el archivo local. El mecanismo final se decidirá después de validar en hardware qué flujo entrega DAT 1.0 y qué calidad/autonomía real obtenemos.

## No incluido en V1
- Streaming público a YouTube/Facebook/TikTok/Instagram.
- Página web del cliente en Floot.
- Edición/publicación automática de clips.
- Compatibilidad prometida con cámaras externas arbitrarias.

## Extensibilidad
CameraSource y los futuros adaptadores permiten añadir otras fuentes de cámara compatibles con iOS sin reescribir la lógica de la sesión.


## Separación estricta de motores de cámara

La integración se organiza en tres capas para evitar mezclar Meta con la cámara del iPhone:

1. **Motor iPhone / DIVISA SHOPPER**: LiveKit, micrófono bidireccional, cámara frontal/trasera y grabación local. No crea DeviceSession de Meta ni interpreta estados del SDK Meta.
2. **Motor Ray-Ban / Meta CameraAccess**: registro, permiso Meta, selección de dispositivo, DeviceSession, Camera, Stream, estados, errores y frames. Debe poder demostrar imagen real independientemente de LiveKit y del grabador de DIVISA SHOPPER.
3. **Coordinador/adaptador**: es el único punto autorizado para tomar frames ya producidos por un motor y publicarlos/grabarlos. Decide qué fuente está activa sin introducir lógica Meta dentro del motor iPhone.

Invariante principal: un fallo, pausa o reinicio de Ray-Ban nunca modifica la implementación interna de captura iPhone ni tumba el audio/Room de LiveKit.

### Orden de refactorización

- Conservar intacta la ruta iPhone que ya funciona.
- Extraer de MetaWearablesManager cualquier responsabilidad de LiveKit o AVAssetWriter.
- Hacer que el motor Meta exponga solamente estado, preview y frames del SDK oficial.
- Conectar esos outputs mediante un adaptador independiente.
- Validar primero Meta -> preview local. Solo después validar Meta -> adaptador -> LiveKit y Meta -> adaptador -> grabación.

## Flujo aprobado de DIVISA SHOPPER (13-10-2026)

**DIVISA SHOPPER es la aplicación y contiene la coordinación interna**; no existe un tercer motor ni una aplicación externa denominada «Coordinador».

1. DIVISA SHOPPER abre y mantiene la sala LiveKit. LiveKit puede conectarse sin cámara publicada; el comportamiento predeterminado es publicar la cámara trasera del iPhone.
2. La aplicación ofrece controles de cámara (iPhone y botón flotante Ray-Ban) y selecciona una fuente de video para la misma sesión sin desconectar audio ni cliente.
3. El motor iPhone y el motor Meta DAT permanecen independientes. El SDK oficial Meta controla registro, permisos, DeviceSession, Stream y entrega de muestras; LiveKit controla la sala y su audio. No modificar los SDK.
4. Una muestra de Ray-Ban solo se considera **imagen disponible** cuando existe un fotograma real, listo y decodificado; Bluetooth conectado o StreamState.streaming no bastan.
5. La grabación local recibe la fuente activa por su propia ruta y **guarda segmentos MOV**. Ante interrupción de Ray-Ban **o iPhone**, debe cerrar y verificar el segmento previo y comenzar otro al recuperarse o cambiar de fuente. Es un requisito obligatorio, pero su implementación y prueba física aún no están completas para ambas cámaras.
6. Si Ray-Ban se interrumpe, conservar la sala LiveKit, proteger el segmento, intentar recuperar la fuente y, tras un tiempo configurable validado con pruebas reales, usar respaldo iPhone. No asumir duraciones de corte o autonomía de Meta.
7. Una imagen o video temporal para el cliente durante cortes queda **pospuesto** hasta demostrar primero video Ray-Ban con el SDK oficial y grabación por segmentos confiable.
8. Estados previstos del botón flotante Ray-Ban: **gris** (no disponible), **amarillo** (detectada/preparando), **verde fijo** (imagen real disponible), **verde intermitente** (fuente Ray-Ban participando en sesión). La grabación local debe tener indicador independiente.

### Orden de implementación y validación

1. Confirmar en hardware Meta -> primer frame decodificado y comparar la versión SDK fijada con el ejemplo oficial CameraAccess.
2. Verificar y proteger segmentos de ambas cámaras, incluido congelamiento iPhone; comprobar integridad MOV y errores de cierre.
3. Fortalecer transición y recuperación sin cortar LiveKit/audio.
4. Terminar controles flotantes y estados verídicos.
5. Después, evaluar imagen de espera y tiempos de respaldo según mediciones físicas.

**Nota:** este documento expresa requisitos y arquitectura; no implica que todos estén implementados o validados.

### Verificación adicional de dependencias y grabación (13-10-2026)

- `project.yml` fija **Meta DAT 1.0.1** mediante `exactVersion`. La etiqueta oficial `1.0.1` existe, pero el árbol de esa etiqueta no incluye el ejemplo `samples/CameraAccess` de la rama principal actual. **No copiar APIs del ejemplo actual suponiendo que existen en 1.0.1.**
- La ruta actual Meta usa `StreamConfiguration(videoCodec: .raw, resolution: .low, frameRate: 24)`. Verificar en compilación y hardware si esa configuración entrega `CMSampleBuffer` con `CVPixelBuffer` utilizable. Si no, investigar decodificación compatible con la versión fijada antes de alterar el puente a LiveKit.
- `LocalVideoRecorder.finishCurrentSegment()` espera `AVAssetWriter.finishWriting()` y solo registra el segmento si el writer termina con `.completed`. No equivale a verificar reproducción, duración, integridad ni comportamiento ante interrupción abrupta del proceso.
- El iPhone envía frames al grabador a través de `IPhoneRecordingVideoProcessor`; aún falta watchdog de pérdida de frames, cierre seguro y pruebas de recuperación de segmentos iPhone.
- **No considerar pruebas completadas** hasta disponer de compilación iOS y resultados en iPhone con Ray-Ban reales. Mantener la pantalla de espera fuera de esta etapa.

## Puerta de validación antes de consumir intentos de instalación en iPhone

**Presupuesto operativo comunicado: quedan diez intentos.** No generar ni instalar una IPA por cada cambio aislado. La siguiente prueba física debe reunir correcciones verificables y diagnósticos claros.

| Criterio | Evidencia necesaria | Estado |
| --- | --- | --- |
| Separación de motores y sala LiveKit | Revisión estática del código | Revisado, no probado en hardware |
| DAT 1.0.1 compatible | Compilación iOS de rama de auditoría y confirmación de APIs | Pendiente |
| Video Ray-Ban real | Primer CVPixelBuffer válido, preview visible y contador creciente en iPhone | Pendiente de hardware |
| Segmentación Meta | MOV finalizado, reproducible y siguiente segmento tras corte | Pendiente de hardware |
| Segmentación iPhone | Watchdog de frames, cierre confirmado, nuevo segmento tras recuperación | Pendiente de implementación y prueba |
| Cambio de fuente | Audio/Room LiveKit sin caída, archivo anterior conservado | Pendiente de prueba |
| Botón flotante | Gris/amarillo/verde fijo/verde intermitente ligados a estados reales | Pendiente |
| Imagen de espera | Fuera del alcance hasta validar lo anterior | Pospuesto |

**Regla de estados:** «implementado», «compila» y «validado físicamente» son estados distintos. No marcar en verde físico sin evidencia. No tocar SDK oficiales, no fusionar a `main` sin revisión y no consumir intentos de instalación sin comprobar antes compilación y dependencias.


## Secuencia oficial Meta DAT 1.0.1 — prueba prioritaria sin LiveKit

Fuente: paquete oficial facebook/meta-wearables-dat-ios, etiqueta 1.0.1; interfaces Swift MWDATCore y MWDATCamera. No sustituir APIs del SDK ni suponer que Bluetooth conectado significa video disponible.

1. **Configuración:** comprobar el proyecto Meta y el `MWDAT.MetaAppID` real. El valor `0` presente en `project.yml` es provisional y debe verificarse antes de probar registro físico; conservar esquema de retorno `divisa-shopper://` y su manejo por la aplicación.
2. **Registro:** botón `Registrar gafas con Meta` llama `MetaWearablesManager.registerGlasses()` → `Wearables.startRegistration()`; al regresar, `handleRegistrationCallback(_:) ` entrega la URL a `Wearables.handleUrl(_:) `.
3. **Permisos:** `checkPermissionStatus(.camera)`; si no concedido, `requestPermission(.camera)`. Si se rechaza, informar y detener sin arrancar cámara.
4. **Sesión del dispositivo:** `AutoDeviceSelector(wearables:)`, `createSession(deviceSelector:)`, `session.start()` y esperar `.started` desde `stateStream()`. No abrir cámara antes de este estado.
5. **Cámara:** `session.addCamera(config: StreamConfiguration(videoCodec: .raw, resolution: .low, frameRate: 24))`; observar `videoFramePublisher`, `statePublisher`, `errorPublisher`, luego `stream.start()`.
6. **Imagen real:** usar `VideoFrame.makeUIImage()` para vista previa local, contar imágenes visibles por separado de `CMSampleBufferGetImageBuffer`. Los frames con pixel buffer y datos listos son los únicos candidatos a grabación/publicación; la vista previa puede tener un resultado distinto.
7. **Ciclo de vida:** cancelar listeners, watchdog y tareas previas al reiniciar; `stopCameraStream()` conserva `DeviceSession` cuando corresponda; `stopRayBanPreview()` detiene todo. No declarar éxito por estado `.streaming` sin imagen.
8. **Después de la prueba:** solo cuando aparezca imagen real en el iPhone, integrar progresivamente LiveKit, grabación MOV segmentada y recuperación/fallback. Cada fase requiere compilación y comprobación separada.

**Puerta de salida:** compilación del simulador no demuestra autorización Meta, conexión Bluetooth, frames reales ni reproducción MOV. No gastar una de las diez instalaciones físicas restantes sin revisar antes configuración Meta y compilación.
