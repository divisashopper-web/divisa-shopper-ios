# Auditoría Meta oficial — fase 3: lifecycle, UI y estado

## Hallazgos del código oficial
### Inicialización
- CameraAccessApp llama Wearables.configure() una sola vez al arrancar y usa Wearables.shared.
- En DEBUG habilita MWDATMockDevice; no forma parte de producción.
- RegistrationView queda separado de CameraView: registro de gafas y sesión de cámara son ciclos distintos.

### Máquina de estados explícita
Meta no trata "conectado" como un booleano único:
1. registrationState
2. hasActiveDevice / compatibilidad
3. DeviceSessionState
4. StreamState
5. hasReceivedFirstFrame
6. isRecording

Esto evita declarar éxito sólo porque el stream diga .streaming. Para DIVISA SHOPPER, la fuente Ray-Ban debe considerarse realmente utilizable sólo cuando sesión + stream + frame reciente sean saludables.

### Ciclo de cámara
- Start Session y Start Preview son pasos separados.
- Stop Preview mantiene DeviceSession.
- End Session es terminal y el SDK hace cascada sobre Camera/Stream.
- Un tap físico puede llevar StreamState a .paused; Meta conserva el último frame y lo comunica como pausa, no como desconexión.
- Al ir a background Meta termina la sesión deliberadamente.

### UI y rendimiento
- Meta aísla LivePreviewView para que las actualizaciones ~24 fps no redibujen controles.
- Timer de grabación usa TimelineView independiente.
- Estados transitorios starting/waitingForDevice/stopping bloquean controles para impedir operaciones superpuestas.
- La UI muestra Session y Stream por separado.

## Consecuencias para DIVISA SHOPPER
1. Reemplazar la noción binaria de `isStreaming` como verdad de salud por una máquina de estados de cámara.
2. Añadir `lastFrameAt`/watchdog: .streaming sin frames recientes no equivale a vídeo saludable.
3. Tratar `.paused` como estado recuperable; no saltar inmediatamente al iPhone por un tap físico.
4. Separar "gafas registradas", "gafas disponibles", "sesión iniciada", "stream activo" y "vídeo recibido".
5. Conservar último frame sólo para UI; LiveKit no debe seguir enviando un frame congelado como si fuera vivo.
6. Evitar operaciones simultáneas start/stop/switch con un coordinador único.
7. No copiar la política background de Meta automáticamente: la llamada LiveKit y requisitos comerciales son diferentes.

## Próxima pieza a diseñar
`ShopperCameraCoordinator` será el único dueño de la selección de fuente y recibirá eventos de `MetaCore` y `LiveKitSessionManager`. El UI no cambiará directamente varias propiedades. MetaCore conservará el lifecycle oficial sin conocer LiveKit.

No se modifica producción en esta fase.
