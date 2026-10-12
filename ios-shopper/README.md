# DIVISA SHOPPER — App del Shopper (iOS)

## Arquitectura objetivo vigente
Meta/Ray-Ban y DIVISA SHOPPER operan independientemente. Meta gestiona de forma nativa las gafas y sus grabaciones; la aplicación privada iOS administra videollamada LiveKit, cámara y audio del iPhone, y videos importados mediante Fotos, Archivos o compartir cuando estén disponibles.

No se asume control de la grabación nativa de Meta, recepción automática de su video ni acceso a archivos internos. El respaldo en iCloud y la publicación al cliente requieren implementación y validación separadas.

**Estado:** decisión de arquitectura documentada; migración del código histórico DAT, compilación y pruebas en iPhone pendientes. No considerar esta descripción evidencia de que el cambio ya funciona en el IPA instalado.

Consultar [ARCHITECTURE.md](ARCHITECTURE.md) para flujo, límites y criterios de aceptación.

## Código histórico
La integración Meta Wearables DAT y el selector Ray-Ban/iPhone pertenecen a la arquitectura anterior y deben auditarse antes de desactivarse. No borrar ni romper LiveKit durante la migración.

## Backend existente
Token endpoint: https://divisa-shopper-ios.onrender.com/token
