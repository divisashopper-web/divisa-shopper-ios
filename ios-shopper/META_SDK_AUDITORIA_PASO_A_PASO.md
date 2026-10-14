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
