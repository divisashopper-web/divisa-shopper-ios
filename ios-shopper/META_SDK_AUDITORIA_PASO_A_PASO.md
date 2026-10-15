# Auditoría paralela Meta DAT 1.0.1 / DIVISA SHOPPER

Estado: auditoría en curso. **No autoriza instalación física.**
Referencia fija: https://github.com/facebook/meta-wearables-dat-ios/tree/1.0.1
Implementación: ios-shopper/project.yml, ios-shopper/MetaWearablesManager.swift.
Criterio: comparar APIs públicas e integración; no intentar replicar frameworks binarios privados.

## Paso 1: dependencia oficial y configuración
- [x] El repositorio oficial 1.0.1 distribuye un Swift Package con MWDATCore y MWDATCamera.
- [x] project.yml usa el paquete oficial con exactVersion: 1.0.1 y vincula ambos productos.
- [x] project.yml declara MWDAT.AppLinkURLScheme = divisa-shopper:// y CFBundleURLSchemes = divisa-shopper.
- [x] project.yml declara MetaAppID = 0 para modo desarrollador; NO equivale a configuración de publicación.
- [x] Info.plist.fragment.xml, excluido del target, ahora coincide en URL scheme divisa-shopper y MetaAppID 0 con project.yml (commit afb6470). Sigue siendo una referencia, no la configuración efectiva. Variables de ClientToken/TeamID permanecen como plantilla, no se atribuye a ellas ningún fallo sin evidencia.
- [ ] Verificar con referencia oficial 1.0.1 cada requisito de Info.plist, callback, entitlements y estado de registro; no basta que compile.\n- [x] La corrección del fragmento auxiliar no modifica el Info.plist generado ni la cámara iPhone.

## Paso 2: registro (lectura inicial de nuestro código)
- [x] MetaWearablesManager.registerGlasses llama wearables.startRegistration().
- [x] MetaWearablesManager.handleRegistrationCallback llama wearables.handleUrl(url).
- [x] Revisado DIVISAShopperApp.swift: configura Wearables.configure() al iniciar y reenvía el callback a wearables.handleUrl(url) mediante el manager.\n- [x] Corregido filtro de retorno: antes exigía query metaWearablesAction; ahora valida solo el esquema divisa-shopper y deja que el SDK oficial interprete el callback (commit 7bf0da7).\n- [ ] Verificar secuencia exacta, configuración de app link y tratamiento del callback contra documentación oficial 1.0.1 y CI; todavía no se ha probado retorno real desde gafas.

## Paso 3: sesión y cámara (pendiente auditoría exhaustiva)
- [x] Código local contiene checkPermissionStatus/requestPermission, AutoDeviceSelector, createSession, stateStream, start, addCamera, stream.videoFramePublisher, statePublisher, errorPublisher.
- [ ] Comparar cada llamada, su orden, errores, tiempos de espera, interrupciones y cierre con documentación y APIs públicas oficiales.
- [ ] Validar muestra real, vista previa y guardado MOV mediante pruebas sin hardware disponibles.
- [ ] Comprobar CI después de cambios.

**Regla de liberación:** ninguna IPA para instalación física hasta cerrar los puntos pendientes que se puedan comprobar sin gafas, registrar las limitaciones y obtener CI exitoso. La compilación no prueba recepción real de fotogramas.

## Paso 4: entrega de frames y grabación local
- [x] Contrastada la interfaz pública real MWDATCamera 1.0.1: StreamConfiguration(.raw/.hvc1), DeviceSession.addCamera, Stream.videoFramePublisher, Stream.statePublisher, Stream.errorPublisher, VideoFrame.sampleBuffer y makeUIImage().
- [x] Se revisó ShopperSessionModel.swift y LocalVideoRecorder.swift. El coordinador entrega buffers válidos a LiveKit y al grabador local.
- [x] Eliminada dependencia adicional de liveKit.activeCameraSource en la ruta de escritura local de fotogramas Meta: ahora depende de grabación activa y fuente Meta seleccionada (commit 3546e1c). No se modifica el motor de cámara iPhone.
- [x] La parada explícita del CameraStream notifica al coordinador si había stream activo (commit b0b793c, CI exitosa).
- [ ] Revisar orden de transición de fuente para evitar perder los primeros frames de grabación y confirmar cierre de segmentos con datos reales.
- [ ] Comprobar CI del commit 3546e1c y efectuar validación de extremo a extremo en dispositivo real antes de declarar recepción de imagen.


## Verificación de ciclo de vida — 14 octubre 2026

- CI de `4ebeade` confirmada exitosa: el cierre de `CameraStream` cancela el observador de `DeviceSession`, y `startCameraStream` instala uno nuevo.
- `CameraStream.statePublisher` distingue `.streaming` de otros estados y emite interrupción solamente si antes transmitía.
- `DeviceSession.stateStream()` contempla `.paused`, `.started` y `.stopped`. Las rutas de pausa y cierre solo notifican pérdida de streaming si estaba activo, para evitar avisos duplicados.
- El watchdog de frames detecta dos segundos sin muestras mientras el stream se reporta activo y notifica interrupción.
- El coordinador deduplica la recuperación con `metaInterruptionPending`, protege el segmento MOV al recibir la interrupción y espera tres segundos antes de intentar reiniciar.
- Pendiente: verificar en dispositivo real la semántica de los estados y que el primer frame de la sesión recuperada abra un nuevo archivo MOV.
- Esta auditoría estática y CI no constituyen prueba de fotogramas físicos de las gafas.


## Auditoría de recuperación y concurrencia — 14 octubre 2026

- [x] CI verificada exitosa para `8b51b24`, `e7d228e`, `ddecb49`, `7252deb`, `e6c615f` y `6a610d1`.
- [x] `ShopperSessionModel.selectCamera` no cancela el plazo de respaldo iPhone cuando rechaza una selección por transición activa (`8b51b24`).
- [x] Volver a seleccionar Ray-Ban durante la espera de recuperación no cancela el respaldo programado (`e7d228e`).
- [x] Una `DeviceSession` obsoleta se detiene al invalidarse la generación de conexión (`ddecb49`).
- [x] Si el reinicio de `CameraStream` no obtiene un primer frame válido, se cierra el intento de cámara fallido antes de reconstruir la sesión (`7252deb`).
- [x] La ruta de espera y la ruta de excepción de `restartCameraStream` comprueban la generación antes de cerrar cámara o sobrescribir diagnósticos (`e6c615f`, `6a610d1`).
- [ ] Auditar la semántica exacta de estados y errores del SDK contra documentación oficial y ejemplo CameraAccess, sin atribuir comportamientos no publicados al SDK.
- [ ] Prueba física: registro, permiso, primer frame válido, vista previa, LiveKit, MOV reproducible, desconexión, reconexión y respaldo iPhone.
- [ ] Verificar Info.plist/entitlements definitivos y configuración de publicación; `MetaAppID = 0` sigue siendo modo desarrollador.

**Alcance de esta evidencia:** CI confirma compilación; no valida fotogramas de gafas físicas, persistencia MOV real ni compatibilidad extremo a extremo.

## Cierre adicional de DeviceSession — 14 octubre 2026

- [x] Commit `b0f7e64`: al terminar `stateStream()` sin `.started`, se detiene siempre la sesión local antigua; únicamente se borra `deviceSession` y se actualiza el diagnóstico si la generación sigue siendo la actual.
- [ ] Confirmar CI del commit `b0f7e64` antes de considerarlo verificado por compilación.
- [ ] Confirmar en gafas reales que las rutas de cierre y reintento no interfieren con el primer frame ni con el MOV.

## Hallazgo de alcance de grabación — 14 octubre 2026

- [x] Verificado en `LocalVideoRecorder.start(source:)`: la ruta V1 de grabación local está configurada explícitamente para **solo video**. El código comenta que capturar un segundo micrófono junto a la sesión de audio de LiveKit produjo cierres en un iPhone físico y se desactivó para estabilizar el video.
- [ ] **No afirmar que el MOV final incluye voz del cliente ni audio bidireccional**. LiveKit mantiene audio en la llamada, pero eso no equivale a audio multiplexado en el MOV local.
- [ ] Diseñar y verificar captura/multiplexación de audio compatible con LiveKit, sin abrir otra sesión de micrófono que provoque conflictos. Mantenerlo fuera de la ruta crítica de primera imagen Meta.
- [x] `archiveCurrentSegmentForInterruption` espera `finishWriting()` y confirma la URL esperada entre los segmentos completados cuando había un writer activo.
- [ ] Validar con archivos MOV reales que los segmentos son reproducibles y que el primer frame posterior a una interrupción inicia un archivo nuevo.

**Decisión de liberación:** primero demostrar video estable y MOV reproducible; el audio bidireccional grabado sigue siendo una función pendiente, no una capacidad certificada.

## Diagnóstico del bloqueo de registro — 15 octubre 2026

**Síntoma físico confirmado:** la app mostró «Error interno — No se pudo completar la operación» durante el flujo de registro Meta; no se recibió primer fotograma. El mensaje genérico no identifica por sí mismo qué subsistema falló.

**Ruta real comprobada en código:** `DIVISAShopperApp.init` invoca `Wearables.configure()` y registra el error únicamente en NSLog; `MetaWearablesManager.registerGlasses` invoca `startRegistration()`; el retorno con esquema `divisa-shopper` pasa a `wearables.handleUrl(url)`. Si falla `configure()`, la interfaz no expone directamente ese error. No asumir que `startRegistration()` puede funcionar tras fallo de configuración.

**Configuración efectiva declarada:** `ios-shopper/project.yml` define `MWDAT.AppLinkURLScheme = divisa-shopper://`, `MWDAT.MetaAppID = 0`, esquema URL `divisa-shopper`, y `LSApplicationQueriesSchemes = fb-viewapp`. El fragmento XML auxiliar está excluido del target; sus valores de ClientToken/TeamID no se aplican automáticamente.

**Brecha relevante:** la auditoría previa del ejemplo oficial CameraAccess identifica entitlements de HotspotConfiguration y wifi-info que no aparecen en project.yml. No añadirlos a ciegas: verificar requisitos exactos y soporte del perfil de firma. Tampoco cambiar MetaAppID sin verificar modo desarrollador/registro del proyecto.

**Próxima intervención de código, antes de una IPA:** registrar de forma visible y distinguible cuatro etapas: (A) resultado de `Wearables.configure()`; (B) resultado de `startRegistration()`; (C) llegada del callback y resultado de `handleUrl`; (D) permiso de cámara. Mantener mensajes técnicos sin exponer credenciales. Verificar compilación en CI. Solo después pedir prueba física; no confundir éxito de compilación con conexión real.

**Estado:** diagnóstico documental; no hay corrección demostrada del registro, ni cambio del flujo de video o grabación.

## Revisión transversal — 15 octubre 2026 (SDK Meta + red + llamada + grabación + firma)

**Alcance revisado en código:** `project.yml`, `MetaWearablesManager.swift`, `DIVISAShopperApp.swift`, `ShopperSessionModel.swift`, `LiveKitSessionManager.swift`, `.github/workflows/ios-shopper-build.yml`. Hallazgos estáticos, NO validación física.

| Subsistema | Evidencia concreta | Riesgo / prueba pendiente |
| --- | --- | --- |
| Inicialización SDK | `Wearables.configure()` en `App.init`, error registrado solo por NSLog | Capturar y mostrar fallo sin introducir errores Swift; el intento anterior `434d362` falló compilación de simulador y archivo iPhone. Revertido en `be861e1` para restaurar entrada anterior |
| Registro Meta | `startRegistration()` y `handleUrl(url)`; callback filtrado por esquema `divisa-shopper` | Verificar registro real, retorno de Meta AI y errores concretos; no atribuir causa a MetaAppID=0 sin evidencia |
| Permisos Meta | `checkPermissionStatus(.camera)`, `requestPermission(.camera)` | Probar regreso de autorización y que no invalide la generación de sesión |
| Transporte gafas | Bluetooth y red local declarados en Info.plist generado; CameraAccess oficial menciona entitlements HotspotConfiguration / wifi-info | Comparar entitlements de muestra y firma; verificar negociación Wi-Fi real, no equiparar internet móvil con enlace local gafas-iPhone |
| Video Meta | `DeviceSession` → `addCamera` → `videoFramePublisher`, codec raw, resolución low, 24 fps | Primer frame físico, CVPixelBuffer válido, preview, caídas, temperatura/batería, compatibilidad firmware |
| Internet iPhone | El acceso a LiveKit requiere endpoint HTTPS de token y conectividad a servidor | Probar 5G/Wi-Fi, cambios de red, pérdidas de paquetes y reconexión; una conexión a internet estable NO garantiza enlace Wi-Fi local Meta |
| Credenciales | `ShopperSessionModel` usa `https://divisa-shopper-ios.onrender.com/token`; `LiveKitSessionManager.connect` distingue errores TOKEN, LIVEKIT y MICRÓFONO | Verificar endpoint, respuestas, URL de sala, JWT y permisos sin exponer secretos; comprobar servicio en Render y tiempos de despertar |
| Publicación LiveKit | Pista iPhone o `MetaToLiveKitBridge` en misma sala; `pushRayBanFrame` solo con CVPixelBuffer | Confirmar pista visible al cliente y evitar dos pistas activas no deseadas durante transición |
| Audio llamada | LiveKit activa micrófono tras conectar; capturador Meta HFP del ejemplo oficial puede competir con AVAudioSession | Prueba de ida/vuelta, Bluetooth y ruta de micrófono; NO habilitar segunda captura de audio sin diseño |
| Grabación local | `LocalVideoRecorder` recibe muestras Meta desde coordinador, protege segmentos ante interrupciones | MOV reproducible y continuidad real; V1 sin audio grabado |
| Fallback | Coordinador intenta recuperación Meta y cámara iPhone sin cerrar la sala | Pruebas de cambio, no duplicación, tiempo de espera, desconexión y nuevo segmento |
| Firma iOS | Workflow valida certificado, perfil y bundle ID; crea IPA de desarrollo y verifica firma | Entitlements reales deben coincidir con provisioning; CI no certifica hardware |
| Privacidad/tiendas | Videollamada y grabación pueden captar terceros | Consentimientos del cliente, normas de cada tienda y tratamiento de imagen/voz de terceros |

**Hallazgo operativo:** el workflow ejecuta simultáneamente build de simulador y archivo para iPhone; una edición Swift compartida puede romper ambos. El run 38770305182 falló en «Build for iOS Simulator» y «Archive for physical iPhone». Sin logs de compilador no afirmar causa concreta. Revertir el cambio fallido permite probar regreso a base compilable.

**Orden de verificación exhaustiva:** (1) CI verde y logs; (2) configuración SDK, callbacks y permisos; (3) conexión local gafas-iPhone; (4) primer frame y preview; (5) conexión remota/token LiveKit; (6) video cliente + audio ida/vuelta; (7) MOV local; (8) cortes de internet/Meta, fallback y reconexión; (9) duración, calor y batería. Registrar resultados independientes por etapa.

**Restricción:** no instalar nueva IPA ni prometer video/audio de dos horas hasta superar pruebas físicas y reproducción de grabaciones.
