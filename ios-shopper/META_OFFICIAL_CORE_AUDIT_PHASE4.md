# Fase 4 — auditoría línea a línea de la integración ACTUAL de DIVISA SHOPPER

Esta fase inspecciona el código existente, después de las fases 1–3 del ejemplo oficial. No sustituye el SDK Meta ni modifica código de producción.

## MetaWearablesManager.swift
| Función | Qué hace hoy | Riesgo concreto | Separación futura |
| --- | --- | --- | --- |
| wearables | accede a Wearables.shared | depende de configuración externa previa | MetaCore |
| registerGlasses | startRegistration() | no observa registro ni compatibilidad del dispositivo | MetaCore |
| startRayBanPreview | limpia sesión, solicita permiso, crea DeviceSession, espera .started, añade cámara raw low 24, listeners y stream.start | operación monolítica; espera stateStream sin timeout; no maneja errores de sesión; hace UIImage por cada frame; reinicia sesión siempre | MetaCore para ciclo oficial, adaptador de frames aparte |
| videoFramePublisher listener | UIImage + CVPixelBuffer; envía a LiveKit y reconstruye CMSampleBuffer con PTS frameCount/24 | conversión UI en ruta crítica; grabación sin timestamps reales; mezcla de responsabilidades | MetaVideoAdapter + RecordingCoordinator |
| statePublisher listener | mapea .streaming a Bool; callback para fallback | una pausa puede tratarse como fallo tras 3s; sin watchdog de fotogramas | MetaCore emite estado tipado |
| errorPublisher listener | sólo actualiza texto | no desencadena recuperación controlada | MetaCore emite error tipado |
| waitUntilFirstFrame | polling 12 s de hasReceivedFrame | una imagen antigua no prueba flujo sostenido | health basada en lastFrameAt |
| waitUntilStreaming | polling 12 s de isStreaming | .streaming no garantiza frames | no usar como criterio único |
| stopRayBanPreview | limpia listeners, camera y session | posible callback asíncrono pendiente tras stop | token/generación para ignorar frames tardíos |

## ShopperSessionModel.swift
| Función | Qué hace hoy | Riesgo concreto | Separación futura |
| --- | --- | --- | --- |
| configureMetaFrameRoutes | conecta callbacks Meta→LiveKit, recorder, preview | graba frames de Meta incluso si cámara activa ya es iPhone; no filtra por fuente activa | ShopperCameraCoordinator |
| onStreamingChanged | espera 3s ante !streaming y hace fallback | paused puede activar fallback aunque Meta esté operativa; estado del SDK sin frames tampoco dispara fallback | watchdog de frames y distinción paused/stopped |
| fallbackToIPhoneCamera | publica iPhone, retira track RayBan | no llama metaWearables.stopRayBanPreview(); Meta puede seguir consumiendo batería/entregando frames al recorder | transición atómica de fuente |
| selectCamera | cambia selectedCamera antes de éxito; publica nueva fuente y retira antigua | si RayBan falla, selector sigue en RayBan aunque LiveKit use iPhone; si isStreaming false, no siempre detiene sesión Meta | preferred vs active vs requested |
| retryPreferredCamera | republica track Meta y espera frame | tras fallo no limpia stream Meta; posible sesión colgada | rollback y cleanup |
| startSession | conecta LiveKit; inicia fuente elegida; fallback si RayBan falla | no limpia stream Meta cuando falla por timeout; selected/preferred/active pueden divergir | coordinador |
| endSession | guarda y cierra grabación, detiene Meta y LiveKit | finalización bloqueada durante cambio de cámara | cola/serialización de transiciones |
| toggleRecording | usa fuente publicada y recorder.start() | grabación puede mezclar formatos/resoluciones de RayBan e iPhone | segmentos por fuente |

## LiveKitSessionManager.swift
| Función | Qué hace hoy | Riesgo concreto |
| --- | --- | --- |
| useIPhoneCamera | publica track cámara nativa o cambia posición | track iPhone puede coexistir temporalmente con RayBan durante switch |
| useRayBanVideo | prepara y publica track puente | activeCameraSource pasa a RayBan ANTES del primer frame |
| pushRayBanFrame | entrega buffer al puente | recibe cualquier frame mientras metaPublication existe, incluso tardío |
| stopRayBanVideo | despublica, reset bridge | limpiar activeCameraSource solo si era RayBan está bien |
| stopIPhoneCamera | despublica track iPhone | asigna activeCameraSource=nil INCONDICIONALMENTE, incluso si RayBan ya estaba activa |
| disconnect | desconecta room y limpia referencias | debe coordinarse con recorder antes de apagar fuentes |

## Invariantes de arquitectura
1. MetaCore no conoce LiveKit, grabador, UI ni cámara iPhone.
2. LiveKit no crea ni destruye DeviceSession de Meta.
3. Sólo el coordinador decide fuente activa. La fuente preferida puede diferir.
4. Grabador sólo recibe frames de la fuente activa, y cierra segmento antes de cambiar formato.
5. El cambio de cámara nunca desconecta room ni desactiva audio.
6. Un frame tardío de una sesión Meta terminada no debe entrar en LiveKit o recorder.
7. Sólo cambiar a respaldo tras comprobar pérdida real de vídeo o fallo terminal, no sólo por estado .paused.
8. Meta SDK permanece como dependencia externa sin modificación.

## Primera corrección de bajo riesgo propuesta (siguiente commit)
- Corregir `stopIPhoneCamera` para que NO borre `activeCameraSource` si la fuente activa ya es RayBan.
- No tocar Meta SDK.
- Luego implementar estado de fuente único y evitar que Meta continúe grabando tras fallback.
- Compilar con CI/Xcode antes de instalación física.

## Verificación
Fuente: ios-shopper/MetaWearablesManager.swift, ios-shopper/ShopperSessionModel.swift, ios-shopper/LiveKitSessionManager.swift (rama main). No se ha compilado ni probado en dispositivo en esta fase.
