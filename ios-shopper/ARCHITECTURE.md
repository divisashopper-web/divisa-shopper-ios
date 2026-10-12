# Arquitectura vigente — separación Meta / DIVISA SHOPPER

## Principio
Meta y sus gafas Ray-Ban funcionan exclusivamente mediante sus mecanismos oficiales. DIVISA SHOPPER no inicia, interrumpe ni controla internamente la captura o grabación nativa de Meta. La app iPhone administra su propia sesión de compra asistida, videollamada, cámara del iPhone y archivos a los que tenga acceso autorizado.

## Responsabilidades
- Meta: conexión oficial de las gafas, cámara y grabaciones nativas, dentro de Meta AI y los servicios oficiales compatibles.
- DIVISA SHOPPER iOS: sesión privada del cliente mediante LiveKit, audio/video del iPhone, controles propios, estado de sesión y gestión de archivos importados.
- Cliente web: acceso a la sesión y, cuando esté implementado, a los videos publicados con autorización.

## Flujo de video Meta
1. El usuario graba mediante el mecanismo oficial de Meta.
2. Al terminar la grabación, Meta procesa/sincroniza el video según sus capacidades.
3. Cuando el archivo esté accesible al usuario mediante Fotos, Archivos o compartir, DIVISA SHOPPER permite importarlo explícitamente.
4. La app copia el archivo a su almacenamiento administrado y verifica que exista y sea reproducible antes de marcarlo como guardado.
5. Copia de seguridad en iCloud y publicación en el backend son operaciones independientes, sujetas a permisos, conectividad y confirmación de éxito.

No se presupone que la app reciba automáticamente una notificación de fin de grabación nativa de Meta ni acceso directo a sus archivos privados. No se promete captura continua de dos horas desde las gafas sin pruebas reales.

## Videollamada
LiveKit administra la llamada privada desde DIVISA SHOPPER. La cámara y el micrófono del iPhone son fuentes propias. No se conecta el flujo interno de Meta a LiveKit en esta arquitectura. La grabación de videollamada, si se implementa, requiere tratamiento separado del archivo de las gafas y consentimiento de participantes.

## Compatibilidad y migración
El código histórico de integración directa DAT debe inventariarse y desactivarse de forma controlada, no eliminarse sin verificar dependencias. No se debe lanzar un build ni afirmar que esta arquitectura está implementada hasta completar migración, compilación y pruebas en hardware.

## Criterios de aceptación
- La app abre una sesión LiveKit sin necesitar conexión de las gafas.
- Meta AI y grabaciones nativas siguen funcionando por separado.
- Se puede importar un video exportado por Meta desde Fotos o Archivos y reproducirlo.
- La interrupción de la llamada no elimina archivos ya importados.
- Los estados guardado, respaldado y publicado se muestran por separado y solo tras confirmación.
