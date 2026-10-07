# Reconocimiento y proveedores

El reconocimiento produce propuestas editables de LaTeX. Ningún adaptador llama al CAS, calcula resultados ni ejecuta el texto de un modelo. El usuario revisa la expresión; el cálculo recibe exclusivamente el AST validado descrito en [contract.md](contract.md).

## Configuración y rutas

El servidor carga `server/.env`. Variables: `PILOT_TOKEN`, `MATHPIX_APP_ID`, `MATHPIX_APP_KEY`, `OPENAI_API_KEY`, `ELEVENLABS_API_KEY` y `OPENAI_INTERPRETER_MODEL` (predeterminado `gpt-6-luna`). No hay sustitución silenciosa de modelo. La falta de una clave produce 503 en REST o `provider_unavailable` en WebSocket. El cliente móvil solo conoce el token del piloto; nunca recibe claves de proveedores.

| Entrada | Ruta del piloto | Adaptador |
|---|---|---|
| Trazos | `POST /v1/recognize/ink` | Mathpix `POST /v3/strokes`, coordenadas con doble envoltorio `strokes.strokes` |
| Foto | `POST /v1/recognize/image` | Mathpix `POST /v3/text` por defecto; `provider=openai` para comparación |
| Voz | `WS /v1/dictation` | Scribe v2 Realtime por defecto; `provider=openai` selecciona `gpt-live-transcribe` |
| Interpretación del dictado | Interna | OpenAI Responses, modelo configurado, salida estructurada estricta |

Las dos rutas REST requieren `Authorization: Bearer PILOT_TOKEN`. Foto usa multipart `image`, `revision` y `provider`; admite PNG, JPEG o WebP hasta 8 MiB. Trazos usa `{ "strokes": [{"x":[...],"y":[...]}], "revision":0 }`, hasta 20 000 puntos y 256 trazos; las coordenadas deben ser finitas y emparejadas. Se comprueba además el límite de 512 KiB de Mathpix para trazos. La revisión se devuelve intacta.

Mathpix conserva su campo de confianza cuando existe. Si está por debajo de 0.8, la propuesta incluye una indicación de revisión. No se inventa confianza para OpenAI. Una respuesta de Mathpix sin `latex_styled` solo se convierte en fórmula si `text` contiene exactamente un bloque matemático; texto mixto pide recortar una expresión. Una respuesta HTTP correcta no significa que la ecuación haya sido reconocida correctamente.

Responses usa `stream=true`, `store=false` y `text.format` con `json_schema`, `strict=true`, propiedades obligatorias `latex` y `ambiguities`, y `additionalProperties=false`. Solo se publica la propuesta después de `response.completed`, validación JSON y comprobación de límites. Se rechazan respuestas truncadas, rechazos, campos extra y comandos de TeX ajenos a la presentación matemática. No hay herramientas de cálculo en la solicitud. Los deltas JSON incompletos nunca se aplican al editor.

## Protocolo de voz y revisiones

En modo voz, el botón de teclado junto al micrófono abre **Editar ecuación** con el teclado matemático. Permite corregir la expresión durante el dictado: la sesión permanece montada detrás del editor y cada cambio manual pasa por las mismas revisiones protegidas. La ecuación visible también recibe las propuestas vigentes. Enter o el botón de cerrar vuelven al dictado sin resolver; el cálculo sigue siendo una acción explícita.

1. Abrir WebSocket y enviar `start` con `token`, `sessionId`, `provider`, `language` (`es` o `en`), `latex` y `revision`. Esperar `ready`; antes de autenticar no se conecta ningún proveedor.
2. Enviar frames binarios PCM16 little-endian, mono, 24 000 Hz, preferiblemente 100 ms/4800 bytes. Máximo dos segundos por frame y dos minutos de audio por sesión. El servidor no remuestrea WAV, AAC ni Opus: enviar PCM sin cabecera.
3. Recibir `transcript` provisional/final y `proposal`. Aplicar una propuesta solo si `baseRevision` coincide con la revisión local; aumentar la revisión y enviar `context` con `source:"proposal"`, `segmentId`, `latex` y la revisión nueva.
4. Una edición manual aumenta la revisión y envía `context` con `source:"manual"`. Se conserva como base del siguiente dictado, se invalidan propuestas anteriores y se establece una barrera de audio. Los finales atrasados anteriores a la edición no se incorporan de nuevo.
5. Para terminar, detener el micrófono y enviar `stop`. Continuar escuchando y confirmando propuestas mientras el servidor completa el último segmento. El servidor cierra después de finalizar el ASR y la interpretación; espera hasta tres segundos el ACK de la propuesta final. `commit` también está disponible sin detener la sesión. Una desconexión abrupta cancela el trabajo pendiente y conserva en el cliente su último borrador.

`source` es una extensión compatible del contrato inicial. Para clientes antiguos, el servidor identifica un ACK comparando revisión y LaTeX con una propuesta emitida. Los clientes nuevos deben enviar la fuente explícita para distinguir una edición manual idéntica a una propuesta.

Los parciales se agrupan en ventanas de 400 ms, con una sola interpretación en curso y una actualización posterior con el texto más reciente. Esto evita cancelar indefinidamente el intérprete durante habla continua. Los finales se procesan inmediatamente y sustituyen el trabajo provisional. Identificadores de sesión, segmento, época de edición y revisión protegen contra respuestas fuera de orden. Un ACK parcial no convierte ese parcial en una nueva base: se reconstruye desde la base original y cada segmento se incorpora una sola vez.

Ambos adaptadores usan commits manuales y un detector de silencios local al backend (el backend es el cliente del ASR). Umbral inicial RMS 450, habla mínima 120 ms, silencio 800 ms y segmentación forzada a los 15 segundos. El audio sigue enviándose antes de detectar el silencio. Un commit espera su final antes de aceptar el siguiente segmento, lo que permite establecer barreras de edición inequívocas; el lector upstream permanece activo. Es una política inicial por calibrar con micrófonos reales, especialmente ante ruido. Los frames entrantes permanecen en el transporte mientras se espera el final.

Scribe recibe `model_id=scribe_v2_realtime`, `audio_format=pcm_24000`, `commit_strategy=manual`, idioma principal y segundo idioma ES/EN. `no_verbatim=false` conserva autocorrecciones. No se activa `transcript_edit` ni keyterms de pago. OpenAI abre una sesión `transcription` con `gpt-live-transcribe`, PCM24k, `languages:["es","en"]`, `delay:"low"` y `turn_detection:null`. El nombre completo GPT-Live corresponde a otro producto conversacional y no se utiliza aquí.

## Errores, privacidad y pruebas

Los errores publicados contienen códigos y mensajes sanitizados; no se devuelven cabeceras, claves ni cuerpos de error de proveedores. No se realizan reintentos automáticos facturables. Los timeout HTTP son de 30 segundos; commits ASR de 15 segundos. Al cerrar el socket se cancelan intérprete, lectores y conexiones upstream. El proceso no guarda audio, fotos ni transcripciones en disco. `store=false` y `improve_mathpix=false` no equivalen a prometer retención cero en todos los proveedores; aplican sus condiciones de cuenta.

Pruebas locales sin red:

```bash
server/.venv/bin/python -m pytest server/tests/test_recognition.py
```

Cubren payloads reales con transportes simulados, autenticación, límites, salidas truncadas, errores sanitizados, cancelación que un proveedor ignora, finales fuera de orden, ACK de parciales sin duplicación, prioridad de edición manual, protocolo de cierre y cierre upstream.

### Comparación con un corpus propio

`scripts/benchmark_providers.py` utiliza las rutas reales del servidor. Por defecto **solo valida** el manifiesto y los archivos; `--run` envía datos y genera cargos. No incluye corpus ni resultados prefabricados. Ejemplo de manifiesto JSON, con rutas relativas al manifiesto:

```json
[
  {"id":"foto-01","kind":"image","file":"foto-01.png","expected_latex":"x^{2}+2x=0"},
  {"id":"tinta-01","kind":"ink","file":"tinta-01.json","expected_latex":"x+1=2"},
  {"id":"voz-es-01","kind":"voice","file":"voz-es-01.wav","language":"es","expected_latex":"x^{2}+2x=0"}
]
```

El archivo de tinta contiene `strokes` con el formato REST. Los WAV deben tener audio no vacío, PCM16 mono a 24 kHz. `providers` es opcional por caso. De forma predeterminada se prueban Mathpix/OpenAI en fotos, Mathpix en tinta y Scribe/OpenAI en voz.

```bash
server/.venv/bin/python scripts/benchmark_providers.py /ruta/corpus/manifest.json
server/.venv/bin/python scripts/benchmark_providers.py /ruta/corpus/manifest.json \
  --base-url http://127.0.0.1:8000 --run --output /ruta/resultados.json
```

Se mide duración completa, primera transcripción, primera propuesta y demora de la última propuesta después del audio. `literal_match` solo ignora espacios: diferencias de mayúsculas o llaves cuentan como distintas, aunque puedan representar la misma expresión. No es una medida de equivalencia matemática ni de precisión de un corpus cuando faltan etiquetas. La comparación representativa pendiente requiere voz humana ES/EN, ruido, dispositivos reales, correcciones y expresiones variadas; evaluar también fidelidad estructural con revisión humana, nunca solo error de palabras.

### Smoke real autorizado: 6 de octubre de 2026

Se probaron las rutas REST y WebSocket a través de una instancia local de Uvicorn, con las claves del usuario. Se usaron únicamente una imagen bitmap artificial, trazos sintéticos y una frase sintetizada localmente por macOS de 2.958 segundos. **Esto valida conectividad/protocolo, no compara precisión de proveedores.**

| Prueba | Resultado observado |
|---|---|
| Foto artificial `x+1=2`, Mathpix | `x+1=2`, confianza 0.6655; se indicó revisar |
| La misma foto, OpenAI | `x + - = 2`, con ambigüedad sobre el símbolo; no coincidió con el original |
| Trazos artificiales, Mathpix | `x+1=2`, confianza 1.0 |
| Voz ES, Scribe → intérprete | `X^{2}+2X=0`; preservó la ecuación, con variables mayúsculas |
| Voz ES, OpenAI → intérprete | `x^2+2x=0`; preservó la ecuación |
| Intérprete Responses directo, `gpt-6-luna` | `x^{2}+2x=0`; acceso al modelo confirmado |

Ambas sesiones de voz enviaron propuesta, recibieron ACK y cerraron. En estas muestras únicas la primera propuesta llegó alrededor de 4.7–5.0 s desde el inicio de conexión y la última aproximadamente 1.6 s después del audio; no son objetivos garantizados ni percentiles. Tras el smoke se añadió una instrucción de preferir variables minúsculas salvo indicación expresa o contexto existente. No se atribuye a esa modificación una mejora medida. Un primer intento de generación de voz dentro del sandbox produjo un WAV vacío; no cuenta como prueba de ASR y ahora el harness rechaza archivos vacíos.

## Referencias oficiales verificadas

- [Mathpix: trazos](https://docs.mathpix.com/reference/post-v3-strokes) y [fotos](https://docs.mathpix.com/reference/post-v3-text).
- [ElevenLabs: protocolo Realtime](https://elevenlabs.io/docs/api-reference/speech-to-text/v-1-speech-to-text-realtime).
- [OpenAI Docs: transcripción Realtime](https://developers.openai.com/api/docs/guides/realtime-transcription), [Structured Outputs](https://developers.openai.com/api/docs/guides/structured-outputs?api-mode=responses) e [imágenes](https://developers.openai.com/api/docs/guides/images-vision).
