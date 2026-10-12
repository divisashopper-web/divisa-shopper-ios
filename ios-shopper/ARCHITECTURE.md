# Arquitectura vigente — Ray-Ban Meta + iPhone + LiveKit

## Decisión recuperada (octubre de 2026)
La sesión privada pertenece a DIVISA SHOPPER en el iPhone. La llamada LiveKit permanece conectada durante cambios de cámara. La cámara trasera/frontal del iPhone sirve para iniciar y como respaldo. Las Ray-Ban Meta aportan video POV mediante el SDK oficial Meta Wearables DAT cuando el flujo de fotogramas está realmente disponible.

## Flujo operativo
1. DIVISA SHOPPER inicia la sala LiveKit y publica video del iPhone.
2. Meta Wearables DAT gestiona autorización y acceso al video de Ray-Ban. Un estado Bluetooth conectado no equivale a fotogramas listos.
3. Solo después de confirmar fotogramas reales se ofrece el cambio a Ray-Ban. El control flotante con indicador verde es un requisito de interfaz PENDIENTE, no una función terminada.
4. Al cambiar de fuente se conserva la sala LiveKit, el audio y la identidad del cliente.
5. Si Ray-Ban deja de entregar video, se toleran pausas transitorias; si persiste la interrupción, se mantiene la llamada y se activa el respaldo del iPhone.
6. Se permite intentar recuperar Ray-Ban y cambiar de nuevo sin finalizar la compra.

## Grabación y protección de archivos
La grabación local es responsabilidad del iPhone y debe sobrevivir a cortes de red. Ante fallos de fuente, la aplicación debe finalizar o continuar el archivo de forma verificable. Nunca afirmar que un video quedó guardado hasta comprobar su escritura y reproducción. No se puede reconstruir video que el SDK nunca entregó. La captura/grabación nativa de Meta y la grabación local de DIVISA SHOPPER son mecanismos distintos; no se promete simultaneidad sin pruebas en hardware.

## Estado real del código
Se restauraron ShopperSessionModel.swift y ShopperSessionView.swift desde el commit histórico f6c9e588 (antes de la regresión que retiró el SDK). Esto restaura el selector Ray-Ban/iPhone, el fallback y el control de reintento anteriores. **No equivale a compilación ni prueba en iPhone.**

## Trabajo pendiente
- Botón flotante Ray-Ban: gris/no disponible hasta recibir video real; verde solo cuando la fuente está lista.
- Validar ciclo de vida de fuente y no mostrar estados de disponibilidad falsos.
- Verificar cierre y reproducción de archivos tras cortes.
- Compilar en CI y probar con Ray-Ban reales en iPhone.
- Completar firma/distribución IPA sin alterar la versión instalada hasta validar la nueva.

## Fuera del alcance de esta fase
Streaming público simultáneo a redes, automatización de publicación y garantías no verificadas de autonomía de gafas.
