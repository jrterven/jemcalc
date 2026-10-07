<p align="center">
  <img src="app/assets/brand/jem-calc-logo.png" alt="Logo de Jem Calc: sigma roja con volumen" width="128">
</p>

<h1 align="center">Jem Calc</h1>

<p align="center">
  Calculadora científica para <strong>Android, iOS y web</strong>.<br>
  Escribe, dibuja, fotografía o dicta una ecuación. Revísala y resuélvela.
</p>

<p align="center">
  <a href="https://calc.jemailabs.com">Abrir el piloto privado</a> ·
  <a href="#capturas-y-usos">Capturas y usos</a> ·
  <a href="#ejecutar-el-proyecto">Instalación</a> ·
  <a href="deploy/README.md">Despliegue</a>
</p>

![Calculadora con teclado visual, resultado e historial](docs/screenshots/teclado.png)

Jem Calc combina una interfaz Flutter con un editor matemático visual, aritmética exacta local, cálculo simbólico mediante SymPy y gráficas interactivas. Comparte la interfaz y el motor matemático entre las tres plataformas, con una paleta roja y temas claro y oscuro.

**Los resultados los calcula un motor matemático determinista.** La IA reconoce e interpreta la entrada: propone una expresión editable y el usuario pulsa **Resolver** para calcularla. Un LLM nunca sustituye al motor de cálculo.

El [piloto alojado](https://calc.jemailabs.com) requiere una clave de acceso. Las apps Android/iOS pueden usar `https://calc.jemailabs.com/api` con su token y una conexión a Internet, sin USB ni una Mac encendida. Este repositorio no incluye las credenciales del servicio.

## Capturas y usos

Las capturas muestran la aplicación web real con su paleta roja y ecuaciones de ejemplo; la vista compacta usa un ancho de 390 px. Los cuatro modos de entrada están disponibles desde los botones inferiores.

### 1. Teclado: cálculo científico y simbólico

Introduce fracciones, raíces, potencias y funciones con las pestañas **Básico**, **Científico** y **Cálculo**. Selecciona la operación y pulsa **Resolver** o Enter. La pantalla de la ecuación se puede maximizar.

- **Calcular** evalúa aritmética racional exacta o aproximaciones numéricas locales.
- **Exacto**, **Simplificar**, **Expandir** y **Factorizar** usan el CAS.
- También puedes resolver ecuaciones, derivar, integrar y calcular límites.
- Cambia entre **RAD** y **DEG** para las funciones trigonométricas.

<p align="center">
  <img src="docs/screenshots/teclado-movil.png" alt="Teclado científico en la vista compacta de Jem Calc" width="320">
</p>

### 2. Escribir: ecuaciones a mano

Selecciona **Escribir** y usa el dedo, el lápiz o el ratón. El lienzo incluye deshacer, rehacer, borrador de trazos y modo **Solo lápiz**. Pulsa **Reconocer ecuación** para enviar los trazos a Mathpix; revisa la expresión reconocida antes de resolverla.

![Lienzo de escritura con la ecuación x + 1 = 2 trazada a mano](docs/screenshots/escritura.png)

### 3. Cámara: fotografiar o cargar una ecuación

Selecciona **Cámara** para capturar una foto o abrir una imagen. Recorta y gira la imagen si hace falta, pulsa **Reconocer** y corrige la propuesta antes de **Resolver**. El reconocimiento de imágenes integrado utiliza Mathpix.

![Imagen de ejemplo preparada en el modo Cámara para reconocer la ecuación](docs/screenshots/camara.png)

### 4. Voz: dictado con edición

Selecciona **Voz**, concede permiso al micrófono y pulsa **Comenzar dictado**. Puedes decir, por ejemplo, «equis más uno igual a dos». La transcripción y la expresión se actualizan durante la sesión; el botón de teclado junto al micrófono permite corregir la ecuación mientras dictas.

Al terminar, revisa la expresión y pulsa **Resolver**. En Configuración puedes elegir Scribe v2 Realtime o GPT Live Transcribe. La interpretación del dictado usa GPT-6 Luna; el cálculo posterior sigue a cargo del motor determinista.

![Modo Voz listo para comenzar el dictado de una ecuación](docs/screenshots/voz.png)

### 5. Gráficas: explorar funciones

Escribe una función como `x^2`, `sin(x)` o `y=x+1` y pulsa **Graficar**. Puedes añadir hasta cuatro curvas, desplazar la vista, hacer zoom y arrastrar los cursores **A/B** para consultar coordenadas y diferencias.

La casilla de cada curva permite ocultarla y volver a mostrarla. El pequeño bote de basura la elimina de la gráfica. Usa **+** para volver al editor y añadir otra función. Las coordenadas y valores de la gráfica son aproximados.

![Gráfica de x al cuadrado y x, con casillas de visibilidad y cursores A y B](docs/screenshots/graficas.png)

### 6. Historial: recuperar cálculos

El historial conserva expresiones, resultados, operación, modo angular y versión del motor. Toca una entrada para reutilizarla. En pantallas amplias aparece junto al editor; en móvil se abre con el icono de historial.

![Historial con una suma y la solución exacta de x + 1 = 2](docs/screenshots/historial.png)

El historial se guarda en cada dispositivo o navegador. Actualmente no se sincroniza entre ellos; borrar los datos del sitio también elimina su historial.

## Qué funciona sin servidor

| Función | Disponibilidad |
| --- | --- |
| Editor y teclado científico | Local |
| Aritmética racional y evaluación numérica | Local |
| Gráficas e historial | Local |
| Álgebra simbólica, ecuaciones, derivadas, integrales y límites | Servidor SymPy |
| Reconocimiento de escritura e imágenes | Servidor y Mathpix |
| Dictado e interpretación de voz | Servidor y proveedores de voz/IA |

En web, el funcionamiento local se refiere a una sesión con la aplicación ya cargada; no implica que el sitio se pueda abrir por primera vez sin conexión.

## Ejecutar el proyecto

### Requisitos

- Flutter 3.44 con Dart 3.12.2 o compatible con `app/pubspec.yaml`.
- Python 3.11 o posterior.
- Android SDK para Android; macOS y Xcode para iOS.
- Android 24+ / iOS 15+ para la configuración actual.
- Credenciales de los proveedores que quieras utilizar. No son necesarias para el cálculo local ni para el CAS.

```sh
git clone https://github.com/jrterven/jemcalc.git
cd jemcalc
```

### 1. Preparar el servidor de desarrollo

```sh
cd server
python3 -m venv .venv
.venv/bin/pip install -e '.[test]'
cp -n .env.example .env
cd ..
```

Edita `server/.env` y configura un `PILOT_TOKEN` aleatorio y las claves de los proveedores que vayas a usar. El token del piloto es independiente de las claves de Mathpix, OpenAI y ElevenLabs. Los archivos `.env`, `.local/` y las claves privadas están excluidos de Git.

En una Mac, con los dispositivos en una red local accesible:

```sh
server/.venv/bin/python scripts/setup_pilot.py
server/.venv/bin/python scripts/run_pilot.py
```

El primer comando detecta la IP de Wi-Fi, crea un certificado TLS de desarrollo y genera `.local/pilot.json`. También puedes indicar la dirección con `scripts/setup_pilot.py --host DIRECCION_IP`. El segundo inicia el backend HTTPS en el puerto **8443**.

Solo el certificado **público** se copia a los assets de la app. Las claves de proveedores permanecen en el servidor. Consulta [la guía del backend](server/README.md) para configuración manual y detalles de seguridad.

### 2. Android e iOS

En otra terminal:

```sh
cd app
flutter pub get
flutter devices
flutter run -d DEVICE_ID --dart-define-from-file=../.local/pilot.json
```

Sustituye `DEVICE_ID` por el identificador del teléfono o iPad. El primer arranque en debug guarda el token en el almacenamiento seguro del dispositivo. Después puedes ejecutar una compilación de piloto optimizada:

```sh
flutter run --profile -d DEVICE_ID --dart-define-from-file=../.local/pilot.json
```

Las compilaciones profile/release no importan tokens desde Dart defines: conservan el guardado o requieren introducirlo en **Configuración**. Para compilar iOS con tu propia cuenta, selecciona tu equipo de firma en Xcode.

El backend de desarrollo requiere que la Mac siga encendida y sea accesible para las operaciones remotas. Los certificados locales caducan a los 30 días; para renovarlos, mueve `server/.tls` a un respaldo privado, repite la configuración y recompila. Un cambio de dirección IP puede requerir el mismo procedimiento.

### 3. Web

Con el backend de desarrollo configurado y ejecutándose:

```sh
cd app
flutter pub get
flutter build web --no-web-resources-cdn
cd ..
server/.venv/bin/python scripts/run_web.py
```

Abre **[http://localhost:5187](http://localhost:5187)**. El puerto local asignado es **5187**; comprueba antes que esté libre o pertenezca a Jem Calc:

```sh
lsof -nP -iTCP:5187 -sTCP:LISTEN
```

El proxy escucha únicamente en `127.0.0.1`, verifica el TLS del backend y añade el token en el servidor. **No pases `.local/pilot.json` como Dart defines al compilar web**: el JavaScript generado es público. No expongas este proxy de desarrollo a Internet.

Usa siempre el mismo origen para conservar el historial del navegador. Cámara y micrófono requieren permiso; para servir la app fuera de localhost se necesita HTTPS. MathLive y Cropper están incluidos localmente, sin depender de una CDN. Recompila la web después de cambiar el código compartido.

## Arquitectura

```text
app/                    Flutter: UI, editor, cálculo local, gráficas y almacenamiento
  lib/math/             AST, parser, evaluador y conversión LaTeX
  lib/features/         Teclado, escritura, cámara, voz, gráficas y ajustes
  lib/core/             Estado, API y adaptadores nativos/web
server/                 FastAPI, SymPy y adaptadores de reconocimiento
deploy/                 Docker Compose, Nginx y guía del piloto alojado
docs/                   Contrato matemático, proveedores y validación
scripts/                Desarrollo local, pruebas web, iconos y benchmarks
```

El cliente convierte la expresión a un AST validado. La aritmética local se evalúa en Dart; las operaciones simbólicas se envían al CAS SymPy, ejecutado en procesos aislados con límites de recursos y tiempo. Los resultados distinguen valores exactos, aproximaciones, ausencia de soluciones, errores de dominio, operaciones no soportadas y tiempos agotados.

El reconocimiento de trazos, fotos o voz produce un borrador editable. La revisión de cambios protege las correcciones manuales frente a propuestas de voz tardías.

| Documento | Contenido |
| --- | --- |
| [Contrato matemático](docs/contract.md) | AST versionado, operaciones y transporte |
| [Backend](docs/backend.md) | CAS y conexión con el servidor |
| [Proveedores](docs/providers.md) | Mathpix, voz, interpretación y comparación de reconocimiento |
| [Editor](docs/editor-notes.md) | MathLive y adaptación a las plataformas |
| [Validación](docs/validation.md) | Pruebas realizadas y verificaciones manuales pendientes |
| [Despliegue](deploy/README.md) | Piloto HTTPS, actualización, acceso y reversión |
| [AGENTS.md](AGENTS.md) | Convenciones de desarrollo y compatibilidad entre plataformas |

Algunas evidencias de validación se conservan como archivos locales privados y no se distribuyen en este repositorio.

## Pruebas

Desde `app/`:

```sh
flutter analyze
flutter test
```

Desde `server/`:

```sh
.venv/bin/pytest
```

Para pruebas de navegador, instala Playwright en un entorno local y ejecuta desde la raíz, con la web y el backend activos:

```sh
node scripts/test_web.mjs
node scripts/test_editor.mjs
```

Los scripts usan Chrome instalado. Si el módulo está en otro entorno, define `PLAYWRIGHT_MODULE` con la ruta absoluta a su `index.mjs`. Los informes y capturas se guardan en `output/playwright/`, excluido de Git.

Las llamadas a proveedores son opcionales y pueden generar cargos: actívalas con `WEB_TEST_PROVIDERS=1` y `WEB_TEST_AUDIO=/ruta/ecuacion-sintetica.wav`. Usa una grabación de «equis más uno igual a dos» seguida de al menos ocho segundos de silencio. El navegador de pruebas utiliza cámara y micrófono sintéticos.

`scripts/benchmark_providers.py` permite comparar reconocimiento con un corpus etiquetado; solo realiza llamadas al añadir `--run`. Las pruebas de integración no equivalen a un estudio de precisión sobre una población de usuarios.

## Alcance del piloto

El CAS admite ecuaciones reales de una variable, sistemas lineales de hasta cuatro variables, sistemas polinómicos cuadráticos de dos variables, derivadas hasta orden tres, integrales de una variable y límites laterales o bilaterales. Para sistemas, separa las ecuaciones con `;` o utiliza una expresión `cases`. Una expresión sin resolver no significa que no existan soluciones.

Todavía no incluye cuentas individuales, sincronización, publicación en tiendas, explicaciones paso a paso, aritmética compleja, matrices generales, ecuaciones diferenciales, gráficas implícitas/3D ni integración con Wolfram. Las pruebas de lápiz físico, accesibilidad y rendimiento sostenido requieren revisión manual.

## Identidad visual y dependencias

El logo maestro está en [`app/assets/brand/jem-calc-logo.png`](app/assets/brand/jem-calc-logo.png). Para regenerar los iconos Android, iPhone/iPad, favicon e iconos de instalación web, ejecuta en macOS:

```sh
node scripts/sync_brand_icons.mjs
```

La paleta roja compartida está en [`app/lib/core/palette.dart`](app/lib/core/palette.dart); los adaptadores MathLive reciben esos mismos colores. Los cambios deben mantenerse compatibles con Android, iOS y web.

MathLive 0.111.0 y Cropper se distribuyen con sus respectivas licencias en sus directorios. Las dependencias Flutter están fijadas en `app/pubspec.lock` y el snapshot de dependencias Python está en `server/requirements-lock.txt`.
