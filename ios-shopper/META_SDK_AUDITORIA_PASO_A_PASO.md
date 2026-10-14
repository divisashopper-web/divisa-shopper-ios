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
- [!] Info.plist.fragment.xml (archivo excluido del target por project.yml) usa **otro esquema**: divisashopper:// y divisashopper, además de variables META_APP_ID/CLIENT_TOKEN/DEVELOPMENT_TEAM. Es documentación obsoleta o contradictoria; la configuración efectiva del target es project.yml. Pendiente decidir si actualizar fragmento para evitar errores futuros.
- [ ] Verificar con referencia oficial 1.0.1 cada requisito de Info.plist, callback, entitlements y estado de registro; no basta que compile.

## Paso 2: registro (lectura inicial de nuestro código)
- [x] MetaWearablesManager.registerGlasses llama wearables.startRegistration().
- [x] MetaWearablesManager.handleRegistrationCallback llama wearables.handleUrl(url).
- [ ] Comparar secuencia exacta, configuración de app link y tratamiento de callback con la referencia oficial, incluido el archivo de entrada de la aplicación.

## Paso 3: sesión y cámara (pendiente auditoría exhaustiva)
- [x] Código local contiene checkPermissionStatus/requestPermission, AutoDeviceSelector, createSession, stateStream, start, addCamera, stream.videoFramePublisher, statePublisher, errorPublisher.
- [ ] Comparar cada llamada, su orden, errores, tiempos de espera, interrupciones y cierre con documentación y APIs públicas oficiales.
- [ ] Validar muestra real, vista previa y guardado MOV mediante pruebas sin hardware disponibles.
- [ ] Comprobar CI después de cambios.

**Regla de liberación:** ninguna IPA para instalación física hasta cerrar los puntos pendientes que se puedan comprobar sin gafas, registrar las limitaciones y obtener CI exitoso. La compilación no prueba recepción real de fotogramas.
