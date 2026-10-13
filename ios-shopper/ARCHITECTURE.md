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
