# Validación del piloto Jem Calc

Fecha del registro: **6 de octubre de 2026**. Resultados automatizados, recorridos en dispositivos y pendientes del piloto privado.

## Resultados encima del teclado — 8 de octubre de 2026

Versión **1.0.9+11**: el resultado del modo Teclado se muestra dentro del visor superior compartido por Android, iOS y web. Conserva formato matemático, aproximación, copia y acceso al dominio y comprobación. Los resultados largos se desplazan dentro de la tarjeta; el visor de la ecuación también puede desplazarse en pantallas pequeñas. El botón Resolver mantiene su altura mientras espera al CAS.

Pasaron el analizador, **62 pruebas Flutter** de presentación del resultado/sugerencias/modelo y **15 pruebas** del gateway. Compilaron web, APK release firmado e iOS profile. Chrome comprobó teclas e iframe inmóviles en **320×600, 390×844 y 1200×850**, con ambos temas: recibir el resultado, copiar el valor exacto, seguir escribiendo, mostrar sugerencias, desplazar `80!` y limpiar. Se comprobó también la espera de una solicitud real al CAS, `d(x²)/dx = 2x` y el acceso a sus detalles. Los seis recorridos existentes de sugerencias pasaron en local, omitiendo únicamente la integral remota. La descarga privada del APK se completó, incluida la redirección tras un intento de clave incorrecta, y su SHA-256 coincidió con el instalador firmado.

El Android no estaba conectado. El iPad estaba emparejado, pero bloqueado y no permitió iniciar la prueba; el usuario pidió continuar sin comprobación física. Las compilaciones móviles no equivalen a una prueba en los dispositivos. Evidencias locales: `output/playwright/result-web-results.json`, `result-stable-390-light.png`, `result-stable-390-dark.png` y `android-result-keyboard-download-results.json`. El README incluye la captura nueva del resultado.

## Teclado fijo con sugerencias — 8 de octubre de 2026

Versión **1.0.8+10**: las sugerencias se muestran dentro del editor, entre la ecuación y las pestañas del teclado, tanto en la pantalla principal como en la ventana de edición. Aparecer, desaparecer o cambiar de una a varias opciones solo modifica el espacio del visor de la ecuación. Los adaptadores Android/iOS y web usan la misma configuración y validan cada selección contra la propuesta vigente.

Pasaron el analizador, **100 pruebas Flutter** de sugerencias/modelo/widgets, **31 comprobaciones** del editor real y **15 pruebas** del gateway. Las compilaciones web, APK release firmado e iOS profile finalizaron correctamente. En Chrome se verificaron **seis recorridos** contra producción: teclas inmóviles mientras se escribe en 320×640, 390×844 y 1200×850; diferencial confirmado e integral por CAS; denominador editable; varios diferenciales; edición modal desde Voz; y destino de un límite. El editor aislado también mantuvo las teclas en 304×380 con ambos temas. La descarga privada del APK se completó y su SHA-256 coincidió con el archivo firmado.

No había Android conectado ni iPad disponible para la comprobación física de esta versión. Evidencias locales: `output/editor-stable-keyboard-results.json`, `output/playwright/completion-web-results.json`, `completion-stable-390.png` y `android-stable-keyboard-download-results.json`. La captura de sugerencias del README se actualizó con la ubicación nueva.

## Corrección de cálculo numérico — 8 de octubre de 2026

Versión **1.0.7+9**: una expresión numérica como `18.33 × 12` se evalúa aunque haya quedado seleccionada la operación Resolver. Resultado exacto: `5499/25 = 219.96`. Las igualdades explícitas y las expresiones con variables siguen usando el solucionador, incluso si una variable desaparece por cancelación. El servidor también acepta correctamente las solicitudes de las apps anteriores.

Pasaron el analizador, **117 pruebas Flutter** del modelo, motor y contrato, y las pruebas Python de CAS, contrato compartido, API y acceso privado. Se compilaron web, APK release firmado e iOS profile. Chrome comprobó el producto sin conexión en temas claro y oscuro; contra producción también verificó `x+1=2`, el cálculo enviado por clientes anteriores y la descarga completa del APK con SHA-256 coincidente. El API conservó el rechazo de solicitudes sin autenticación y respondió correctamente usando el token nativo.

No había Android conectado ni iPad disponible para validar físicamente esta versión. El backend LAN tampoco estaba disponible; las pruebas remotas se hicieron contra `https://calc.jemailabs.com`. Evidencias locales: `output/playwright/numeric-solve-results.json`, `numeric-solve-light.png`, `numeric-solve-dark.png` y `android-numeric-solve-download-results.json`. El despliegue vigente y su reversión se documentan en [deploy/README.md](../deploy/README.md); los apartados siguientes conservan el registro original del 6 de octubre.

## Despliegue privado en calc.jemailabs.com

Se publicó **https://calc.jemailabs.com** en `juan@prod`, con la elección explícita del usuario de mantener un piloto privado con clave. El registro A de Cloudflare apunta al servidor dedicado con proxy activo; se verificó SSL **Full (strict)** y el certificado wildcard del origen. Se agregó únicamente el virtual host de calc y un contenedor independiente, con listener `127.0.0.1:5188`, estado healthy y reinicio automático. Jemailabs, JemNotebook, JemIntel y JemClip siguieron respondiendo tras la recarga de Nginx.

El gateway de producción conserva el API por token de Android/iOS y agrega sesiones web firmadas, caducidad de siete días, cookies HttpOnly/Secure y comprobaciones de origen. Los límites de cuerpo originales siguen aplicándose bajo `/api`; Nginx limita solicitudes y conexiones. Pasaron **48 pruebas** de acceso, CAS y reconocimiento, y nuevamente las seis pruebas del gateway tras ajustar la política de referencia del formulario. Chrome enviaba `Origin: null` con `no-referrer`; la política ahora conserva el origen del formulario y sigue rechazando solicitudes de otros sitios. Se comprobaron rechazo de API sin token, login desde origen ajeno, TLS público y un cálculo autenticado con el token nativo. Ningún secreto configurado apareció entre los **91 archivos** del build web. Las credenciales están en el `.env` privado del servidor y en `.local/`, fuera de las imágenes y los archivos públicos.

En Chrome contra el dominio real pasaron los **7 recorridos**: teclado/cálculo local, ecuación por SymPy, persistencia y visibilidad de gráficas, escritura con reconocimiento Mathpix, cámara/crop y reconocimiento de una imagen sintética, voz sintética por WebSocket y viewport móvil. La prueba de voz transmitió **344064 bytes PCM**, recibió transcripción y propuestas editables, sin eventos de error. Las imágenes y el audio fueron sintéticos; no se activó el micrófono ni la cámara físicos. Evidencia: `output/playwright/production-results.json`, `output/web-production-providers.log`, `output/playwright/production-live.png` y `production-cloudflare-dns.png`. Se ajustó el test para esperar a MathLive y enfocar su entrada antes de pulsar el teclado virtual a través de Internet.

El Android conservó su token y borrador, guardó **https://calc.jemailabs.com/api**, comprobó «Servidor disponible · ok» y derivó `sin(x²)` → `2x cos(x²)` exactamente desde el servidor dedicado; se restauró la operación Calcular. Evidencias: `.local/android-production-connection.png`, `android-production-cas.png` y `android-production-final.png`. El modelo real del iPad también guardó la URL pública y resolvió `x+1=2` → `{1}` exacto por SymPy; se restauraron su borrador y operación. Evidencia: `.local/ipad-production-cas.json`. Después se compiló, instaló e inició nuevamente el iPad en **profile**, conservando esos ajustes.

La versión del servidor registrada el 6 de octubre fue `jemcalc:20261006-pilot-3`. Mantenimiento y recuperación: `deploy/README.md`. Las aplicaciones ya no necesitan que la Mac esté encendida ni compartir su Wi-Fi; las funciones remotas necesitan Internet. El historial sigue siendo local a cada dispositivo/origen y no se sincronizó con el nuevo dominio.

Ante una pestaña del usuario que terminó en `file:///access`, se sustituyeron las redirecciones relativas de acceso, login y logout por URLs HTTPS absolutas construidas desde el origen configurado. Se verificó públicamente `Location: https://calc.jemailabs.com/access`; las siete pruebas del gateway incluyen todos esos destinos y rechazan el uso de cabeceras reenviadas para construirlos. Una sesión nueva de Chrome siguió la redirección, inició sesión con clave y realizó un cálculo autenticado correctamente. Evidencia: `output/playwright/production-redirect-check.json`. Se abrió una pestaña HTTPS nueva para el usuario; no se accedió al archivo local inexistente.

## Resultado automatizado

| Comprobación | Resultado registrado | Alcance |
|---|---|---|
| `flutter analyze` | Sin incidencias | Código Dart del proyecto |
| Pruebas Flutter | **112 aprobadas** | Motor local, parser, contrato compartido con CAS, modelo, revisiones, gráficas, widgets y rutas del API |
| Pruebas Python | **114 aprobadas** | CAS, dominios, validación de AST, aislamiento, API, proveedores y proxy web HTTP/WebSocket |
| Editor en Playwright/Chrome | **16 comprobaciones aprobadas** | MathLive y assets locales, escritura, Enter, foco, pestañas, idioma, etiquetas científicas, restauración y tamaños táctiles |
| Webapp completa en Chrome | **7 recorridos aprobados** | Teclado, CAS, gráfica persistente, tinta, cámara/recorte, voz y pantalla de 360×800 |
| Regresión del modelo tras corregir el teclado | **30 aprobadas** | Incluye cuatro casos nuevos de restauración del teclado al cambiar de modo o reconocer tinta/foto; `flutter analyze` también pasó |

Las comprobaciones matemáticas incluyen racionales exactos, dominios reales, DEG/RAD, raíces, límites de tamaño y casos compartidos entre Dart y Python. Las pruebas del modelo verifican que cambios de ecuación, operación o variable invalidan respuestas antiguas; también cubren propuestas de reconocimiento, restauración del historial y cambios de tinta/foto mientras hay un reconocimiento pendiente. Las pruebas de gráfica comprueban cortes en polos y dominios, continuidad de curvas sencillas, transformaciones de zoom/pan y un solo lote de muestreo activo.

Las pruebas de widgets reproducen la conexión entre `AppModel` y el lienzo: el primer trazo persiste al levantar el dedo, activa Deshacer/Reconocer y permite seguir escribiendo después de deshacer o borrar. El modo Solo lápiz se comprobó con eventos de puntero simulados.

El detalle de las pruebas del editor en Chromium y sus capturas está en [editor-notes.md](editor-notes.md).

## Webapp y compatibilidad compartida

La web se compiló con `flutter build web --no-web-resources-cdn` y se sirvió en **http://localhost:5187**. Se comprobó previamente que 5187 estaba libre en IPv4/IPv6 y no aparecía asignado en las configuraciones revisadas de otros proyectos de `/Users/juanterven/dev`. `AGENTS.md` registra el puerto y exige compatibilidad Android/iOS/web para los cambios posteriores.

`scripts/test_web.mjs` ejecutó siete recorridos contra el build Flutter real, con IndexedDB y el proxy real del CAS. Los resultados quedaron en `output/playwright/web-results.json`, sin errores JavaScript:

- Teclas virtuales `1+2` → `3` local y teclado físico `x+1=2` → `{1}` exacto y verificado por SymPy.
- Añadir curvas, ocultar/mostrar por casilla, recargar conservando la lista y visibilidad, borrar una curva y conservar el historial de cálculos.
- Trazos sintéticos con ratón `x+1=1` → propuesta Mathpix, seguida de vuelta al teclado con sus teclas visibles.
- Cámara simulada de Chromium → captura y recorte. Archivo artificial `x+1=2` → selector de archivos, recorte y propuesta Mathpix.
- Audio de voz sintetizado localmente → captura PCM del plugin web, WebSocket, transcripción e interpretación → propuesta editable `X+1=2`. La prueba transmitió **337920 bytes PCM** durante unos siete segundos y terminó la sesión. No usó un micrófono físico ni resolvió automáticamente.
- Vista compacta de **360×800** con pestaña científica y botón Resolver visibles; revisión visual adicional de escritorio a **1200×850**.

Las cinco pruebas del proxy verifican el token añadido únicamente en el servidor, validación de host/origen, límite de cuerpo, HTTPS al backend y transferencia/cierre de audio y transcripciones. La revisión de **259 archivos** fuente y del build web no encontró las credenciales configuradas en `server/.env`.

La Mac cambió a la red `192.168.68.112`: se renovó el certificado público del piloto y se actualizó la URL del iPad, conservando su token e historial. El modelo real del iPad, en debug y con el nuevo transporte, calculó `x+1=2` → `{1}` exacto por SymPy sin error; después se restauró su borrador. Evidencia: `.local/ipad-web-cas.json`. Las compilaciones Android e iOS también se comprobaron. El Android no estaba conectado durante esta actualización web: su compilación no equivale a una nueva prueba física.

Esta validación del navegador corresponde a Chrome con cámara y audio simulados. No certifica micrófonos/cámaras físicos, Safari/Firefox, Apple Pencil ni un despliegue público. La web funciona como piloto local de la Mac; los requisitos de publicación se describen en el README.

Al terminar se instaló e inició en el iPad la compilación **profile** final con los adaptadores compartidos y el certificado actualizado. El APK Android **profile** también quedó compilado; su instalación y el cambio de URL se completaron posteriormente al reconectar el teléfono, como se registra en la actualización de identidad visual.

## Actualización de identidad visual

El usuario aprobó una sigma roja con volumen generada con la herramienta integrada Image Gen. El original está en `app/assets/brand/jem-calc-logo.png`, con el prompt en `identity.json`. Se incorporó a los iconos Android (incluido el adaptativo), al catálogo iPhone/iPad y a los iconos/favicon de la web. Se verificaron los tamaños del catálogo y que el icono iOS de 1024 px no contiene canal alfa.

La paleta roja se comparte desde `JemPalette`, incluidos los colores enviados al editor MathLive nativo/web y las curvas en claro/oscuro. Se revisó la web en ambos temas y se restauró la preferencia Sistema. El analizador pasó sin incidencias; las 16 comprobaciones del editor, las 12 pruebas de gráficas y los 6 recorridos web sin llamadas de reconocimiento pasaron. Evidencias: `output/playwright/red-light.jpg`, `red-dark.jpg`, `web-mobile.png` y `web-graph.png`. No se repitieron los proveedores de reconocimiento/voz para esta actualización visual.

El recorrido web detectó una carrera al alternar rápidamente Escribir → Teclado → Cámara: el cambio de foco al iframe podía poner Flutter en `inactive` y cancelar la inicialización de cámara. La web ahora cierra la cámara cuando la página está oculta; los clientes nativos también la cierran al entrar en `inactive`. Se evita reinicializar una cámara ya existente al recuperar el foco. El mismo recorrido completo pasó después de la corrección.

Las compilaciones Android/iOS/web de esta revisión pasaron. El iPad recibió la identidad visual; su verificación táctil completa sigue fuera de esta revisión.

Tras activar la depuración USB, se instaló en el **ZTE 7060** el APK **profile** final mediante actualización, conservando los datos. Se comprobó la interfaz roja y se corrigió el margen del icono adaptativo con un inset de 16.67% para que el lanzador circular muestre la sigma completa; se recompiló, reinstaló y verificó visualmente. Se actualizó la URL a `https://192.168.68.112:8443`, conservando el token, y la prueba de conexión devolvió «Servidor disponible · ok». Desde la app física, Derivar sobre `sin(x²)` devolvió `2x cos(x²)` exacto. Se conservó el borrador original, se restauró la operación Calcular y se dejó abierta la app final. Evidencias: [icono final](../.local/android-red-icon-final.png), [CAS](../.local/android-red-cas.png), [conexión](../.local/android-red-connection.png) e [instalación final](../.local/android-red-installed.png). No se repitieron las capturas de cámara o voz en esta instalación.

## Android físico

Dispositivo utilizado: **ZTE 7060 con Android 13**. Las interacciones indicadas se hicieron sobre la app instalada; varios toques y trazos se inyectaron mediante ADB.

| Recorrido | Resultado observado |
|---|---|
| Teclado táctil → ecuación → CAS por HTTPS | `x+1=2` produjo el conjunto solución `{1}` |
| Gráfica | `x*x` mostró la curva y se comprobó el cursor A |
| Escritura → Mathpix → revisión → CAS | Ocho gestos de trazo formaron `x+1=1`; Mathpix devolvió una propuesta editable y el CAS produjo `{0}` |
| Cámara | Permiso y vista previa funcionando |
| Galería → recorte nativo → Mathpix | Una imagen artificial de 900×300 px produjo `x+1=2`; propuesta confirmada en la interfaz |
| CAS posterior a la foto | El primer intento tras reiniciar el backend falló por conexión cerrada. Un único reintento desde el `AppModel` real mediante la VM produjo `{1}`, **exacto y verificado**, en **897 ms** |
| Dictado mediante el micrófono del teléfono | Tras autorización explícita se abrió una sesión y la interfaz volvió a Comenzar sin errores, pero no apareció transcripción. La duración registrada excedió la prueba solicitada y hubo otra activación posterior; se cerró la app y se confirmó que el micrófono quedó inactivo. El reconocimiento de habla real sigue sin validar |
| Editor del modo de voz | Se abrió el teclado matemático junto al micrófono y se corrigió `x+1=2` a `x+1=3`. Enter cerró el editor conservando el modo de voz, sin calcular ni grabar audio. Después se resolvió explícitamente y se obtuvo `{2}` |

Durante la comprobación del lienzo se detectó que el modelo no notificaba el nuevo trazo a la interfaz al terminar el gesto. Se añadió la notificación en `updateInk()` y captura opaca de punteros en el lienzo. Las pruebas de regresión cubren el recorrido desde un lienzo vacío y sus herramientas.

El error del primer cálculo de la foto fue `Connection closed before full header`. **Reiniciar el backend durante el piloto puede requerir repetir el cálculo.** La recuperación se comprobó con el reintento indicado, no con un recorrido de interfaz sin fallos.

La compilación Android **profile** está instalada e iniciada. Se comprobó la carga del editor, el cálculo `x+1=2` → `{1}` por HTTPS y volver del fondo sin que se abra Gboard. Evidencia: [android-profile-result.png](../.local/android-profile-result.png).

La corrección táctil del modo de voz y el resultado posterior están en [android-voice-corrected.png](../.local/android-voice-corrected.png) y [android-delivery.png](../.local/android-delivery.png). El analizador volvió a pasar después de integrar este editor.

La actualización posterior del teclado está instalada en Android en modo **profile**. Se revisaron las cuatro columnas, teclas mayores y etiquetas científicas completas. Se reprodujo pantalla maximizada → Escribir → Teclado: reaparecieron las teclas, manteniendo `y=mx+b`, la pestaña científica y los trazos originales. Evidencias: [teclado básico](../.local/keyboard-fixed-installed.png), [científico](../.local/keyboard-scientific-fixed.png), [modo Escribir](../.local/keyboard-write-transition.png) y [teclado restaurado](../.local/keyboard-restored-from-write.png). El acceso superior muestra ahora el texto **Graficar**. Para una recta se puede escribir `y=2x+1`; los parámetros `m` y `b` requieren valores numéricos. El graficador actual acepta funciones de `x` o ecuaciones explícitas `y=f(x)`.

Después de volver desde Escribir, se pulsó `x` y se comprobó la entrada en el editor; se borró esa tecla para restaurar el borrador original. También se maximizó otra vez y se tocó el botón Teclado ya seleccionado: las teclas reaparecieron. Capturas: [entrada tras volver](../.local/keyboard-restored-typing.png) y [restauración al repetir Teclado](../.local/keyboard-reselected-restored.png).

Por la revisión posterior de espacio, se eliminó la fila «Jem Calc» y se reunieron sus acciones en la misma fila que Graficar. Las teclas mantienen cuatro columnas y pasan a 46 px de alto, con separación de 4 px; ya no crecen para ocupar el espacio extra del editor. En Chrome, un viewport de 360×560 dejó 268 px para la ecuación y 292 px para el teclado. Se revisó una expresión con dos fracciones y una raíz en `output/playwright/editor-long-compact.png`. Pasaron nuevamente las 16 comprobaciones del editor y `flutter analyze`. Se verificaron las distribuciones básica y científica en el Android actualizado, conservando el borrador original: [distribución compacta](../.local/keyboard-compact-final.png) y [científico compacto](../.local/keyboard-compact-scientific.png). La versión final integra también el color de la barra de estado al quitar el AppBar.

## Visibilidad de ecuaciones en la gráfica

Cada ecuación tiene una casilla para mostrar u ocultar su curva sin eliminar la fila. La papelera elimina la entrada de la lista de gráficas; no borra el historial de cálculos. Se guarda la lista y el estado de las casillas en preferencias. Los cursores usan la primera ecuación visible; cuando todas están ocultas, muestran `—` en las coordenadas y. Ocultar curvas conserva los índices utilizados para sus colores.

`flutter analyze` pasó sin incidencias. Las pruebas dirigidas de modelo y gráficas aprobaron **43 casos**, incluidos ocultar/restaurar, ocultar todas, cursores, borrado mediante papelera y conservación de la lista al volver a cargar el modelo.

Se instaló la actualización en Android y iPad. En Android se restauraron las curvas `cos(x)` y `sin(x²)` que estaban en pantalla antes de actualizar. Se ocultó `cos(x)`, conservando su fila y el color de `sin(x²)`; los cursores pasaron a esta última. Tras cerrar forzosamente y abrir la app, ambas entradas y el estado de sus casillas permanecieron iguales. Finalmente se volvieron a mostrar ambas curvas. Evidencias: [curvas visibles](../.local/graph-checkboxes-visible.png), [una curva oculta](../.local/graph-checkbox-hidden.png), [estado recuperado tras reiniciar](../.local/graph-visibility-restored.png) y [estado final](../.local/graph-visibility-final.png). El borrado con papelera se validó mediante pruebas de widgets; la interacción física de esta actualización se comprobó en Android.

## iPad físico

Dispositivo con **iOS/iPadOS 26.7.1**. La compilación optimizada **profile** está compilada, instalada e iniciada. Antes de esa instalación, una comprobación de `AppModel` mediante el servicio de la VM confirmó la corrección de carga del certificado PEM: `x+1=2` llegó a SymPy por TLS y devolvió un resultado **exacto y verificado** en **1683 ms**.

La comprobación ejecutó el modelo real en el iPad; no recorrió su interfaz táctil ni utilizó Apple Pencil.

La actualización posterior del teclado también se compiló, instaló y abrió en el iPad inalámbrico en modo **profile**. La revisión visual y las transiciones táctiles de esta actualización se comprobaron en Android; no se repitieron sobre la interfaz del iPad.

## Proveedores reales

Se realizaron llamadas autorizadas a Mathpix, OpenAI y ElevenLabs usando una imagen artificial, trazos sintéticos y una frase de voz sintetizada localmente. Las rutas REST y WebSocket devolvieron propuestas; las sesiones de voz recibieron confirmación y cerraron. Los resultados concretos, incluida una discrepancia de OpenAI en la foto de ejemplo, están en [providers.md](providers.md#smoke-real-autorizado-6-de-octubre-de-2026).

Las dos cadenas de voz funcionaron con audio sintetizado: Scribe → intérprete y OpenAI Transcribe → intérprete. El usuario autorizó después una prueba de cinco segundos con el micrófono Android hacia ElevenLabs y el intérprete OpenAI. La primera captura registró aproximadamente 21 segundos en Android, aunque el controlador envió detener cinco segundos después de su toque de concesión del permiso. No apareció transcripción. Una comprobación posterior detectó otra sesión activa; se detuvo Jem Calc mediante `force-stop` y AppOps confirmó que ya no había captura activa. El usuario confirmó que interactuó directamente con el teléfono durante la prueba. Hubo control manual y automatizado, por lo que estas duraciones no corresponden a una prueba controlada de cinco segundos. La segunda sesión duró aproximadamente 56.1 segundos hasta el cierre forzado. La inspección del cliente encontró `start()` conectado únicamente al botón, sin inicio automático ni reintentos; los metadatos no identifican el disparador de cada sesión. El agente no inició otra captura después de detectar el desfase. Al reabrir la app tras la interacción manual, el borrador conservado fue `X+1=2`, coincidente con la frase de prueba; se pulsó Resolver y SymPy devolvió `{1}` exacto y verificado. Las capturas son [android-after-mic-test.png](../.local/android-after-mic-test.png) y [android-voice-equation-solved.png](../.local/android-voice-equation-solved.png). El estado final confirmó el micrófono inactivo. Este recorrido acredita la ecuación conservada y su cálculo, pero no permite atribuir cada cambio a una sesión concreta ni certificar el límite de cinco segundos.

El reconocimiento devuelve una ecuación editable. El resultado matemático se obtiene posteriormente del motor local o del CAS mediante un AST validado; estas pruebas no usan una respuesta del LLM como solución matemática.

## Evidencias locales y manejo de credenciales

Las evidencias de dispositivo están en **`.local/`**, directorio excluido de Git. Entre los archivos disponibles para revisión en esta copia de trabajo están:

- Android, teclado y CAS: [android-physical-input.png](../.local/android-physical-input.png), [android-calculation-solve.png](../.local/android-calculation-solve.png) y [android-cas-connected.png](../.local/android-cas-connected.png).
- Android, gráfica y cursor: [android-graph.png](../.local/android-graph.png) y [android-cursor.png](../.local/android-cursor.png).
- Android, tinta y reconocimiento: [android-handwriting.png](../.local/android-handwriting.png), [android-mathpix-proposal.png](../.local/android-mathpix-proposal.png) y [android-handwriting-solved.png](../.local/android-handwriting-solved.png).
- Android, cámara y reconocimiento de foto: [android-camera-permission.png](../.local/android-camera-permission.png), [android-camera-active.png](../.local/android-camera-active.png), [android-gallery.png](../.local/android-gallery.png), [android-crop.png](../.local/android-crop.png) y [android-photo-proposal.png](../.local/android-photo-proposal.png).
- iPad, resultado del método de la app: [ipad-e2e.json](../.local/ipad-e2e.json).
- Editor aislado: `output/playwright/editor-mobile.png` y `output/playwright/editor-final.png`, también excluidos de Git.

Estos enlaces locales no estarán disponibles en una copia que contenga únicamente los archivos versionados. No publicar `.local/` completo: contiene además la configuración privada de emparejamiento del piloto, no sólo capturas.

La revisión final de **153 archivos fuente** no detectó filtraciones de las credenciales revisadas. Las claves de proveedores permanecen en `server/.env`, excluido de Git; la configuración privada del piloto y las claves TLS también están excluidas. La app incorpora el certificado público de desarrollo para verificar TLS.

## Reproducir las comprobaciones

Con Flutter, Python y las dependencias del proyecto ya instalados, ejecutar desde la raíz del repositorio:

```sh
cd app
flutter analyze
flutter test
```

En otra terminal situada en la raíz:

```sh
server/.venv/bin/python -m pytest server/tests
node scripts/test_editor.mjs
```

El script del editor requiere una instalación existente de Playwright y Chrome. Si el módulo no está en la ruta habitual, configurar `PLAYWRIGHT_MODULE` como explica [editor-notes.md](editor-notes.md). El script no descarga navegadores ni utiliza proveedores facturables.

Para el piloto físico, seguir [README.md](../README.md) y mantener la Mac y el dispositivo en una red accesible. El servidor privado se inicia desde la raíz con:

```sh
server/.venv/bin/python scripts/run_pilot.py
```

En otra terminal:

```sh
cd app
flutter devices
flutter run -d DEVICE_ID --dart-define-from-file=../.local/pilot.json
```

`DEVICE_ID` se sustituye por el identificador del dispositivo elegido. La configuración debe existir previamente; no pegar tokens ni claves en comandos, capturas o archivos fuente. Las llamadas de reconocimiento usan los proveedores configurados y pueden generar cargos; no forman parte de las baterías de Flutter/Python.

Recorridos de comprobación manual: escribir `x+1=2` y resolver; graficar `x*x` y mover un cursor; escribir trazos, reconocer, revisar y resolver; seleccionar la imagen de prueba, recortar, reconocer y resolver. Para dictado, comprobar permisos, transcripción, edición manual durante la sesión y conservación de la última frase antes de resolver explícitamente.

## Pendientes y límites de aceptación

- **Corpus comparativo no realizado:** faltan las 200 imágenes y los 100 dictados humanos etiquetados. El harness existe; no hay una tasa de precisión comparativa medida ni un ganador establecido entre proveedores.
- **Interacción física incompleta:** Apple Pencil, edición/cámara/permisos en iPad, accesibilidad con lectores de pantalla y dictado completo con micrófonos móviles siguen pendientes. Las pruebas de Chrome y punteros simulados cubren sus entornos concretos.
- **Voz en condiciones reales:** no se han certificado ruido de habitación, cambios de idioma, acentos, interrupciones o correcciones prolongadas con personas.
- **Rendimiento:** no se han certificado 60 fps sostenidos, latencias por percentiles, consumo energético ni sesiones largas en ambos dispositivos. Una duración individual no constituye un presupuesto de rendimiento.
- **Gráficas:** el muestreo es numérico y acotado; puede omitir detalles extremadamente estrechos o de alta frecuencia. Las pruebas de polos no demuestran continuidad para cualquier expresión.
- **Ámbito matemático:** se conserva el alcance y las restricciones descritos en [backend.md](backend.md) y [contract.md](contract.md). Una comprobación numérica o inconclusa no debe presentarse como prueba formal universal.
