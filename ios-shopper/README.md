# DIVISA SHOPPER — App del Shopper (iOS)

Primera versión nativa de la aplicación privada del Shopper.

## Arquitectura V1
- La sesión pertenece al iPhone.
- LiveKit mantiene la videollamada privada con el cliente.
- Fuente de video seleccionable: Ray-Ban Meta, cámara trasera del iPhone o cámara frontal.
- Si las gafas fallan, la llamada continúa y se cambia a iPhone.
- La app recibe y muestra el video remoto del cliente.
- La grabación se diseña independiente de la conectividad para que una caída de llamada no implique perder el material local.

## SDKs previstos
- Meta Wearables Device Access Toolkit 1.0: MWDATCore + MWDATCamera.
- LiveKit Swift SDK 2.x.

## Requisitos actuales de Meta
El sample público de CameraAccess de Meta requiere iOS 17.2+, Xcode 26.4+ y Swift 6.3+.

## Backend
Token endpoint: https://divisa-shopper-ios.onrender.com/token
