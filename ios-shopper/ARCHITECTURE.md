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
