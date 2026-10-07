# Editor MathLive: verificación real de DOM

El editor usa `app/assets/editor/index.html` y MathLive 0.111.0 empaquetado en `app/assets/mathlive`. La prueba utiliza Chrome en un perfil temporal, sirve únicamente los assets locales y bloquea cualquier solicitud fuera de localhost. No utiliza proveedores de reconocimiento, APIs facturables ni contenido de otras aplicaciones.

## Ejecutar

Se requiere Node y una instalación existente de Playwright. El script **no descarga dependencias ni navegadores**. Usa Chrome instalado por defecto:

```bash
node scripts/test_editor.mjs
```

Cuando Playwright existe fuera del proyecto, indicar su módulo:

```bash
PLAYWRIGHT_MODULE=/ruta/instalada/playwright/index.mjs node scripts/test_editor.mjs
```

En la Mac usada para esta verificación, el módulo ya estaba disponible en la caché de Playwright CLI:

```bash
PLAYWRIGHT_MODULE=/Users/juanterven/.npm/_npx/31e32ef8478fbf80/node_modules/playwright/index.mjs \
  node scripts/test_editor.mjs
```

Opciones de entorno: `PLAYWRIGHT_BROWSER_CHANNEL` selecciona otro canal Chromium instalado; `PLAYWRIGHT_BROWSER_EXECUTABLE` permite una ruta explícita a un ejecutable existente. El script inicia su servidor estático en un puerto efímero, lo cierra al terminar y devuelve código 1 si alguna comprobación falla.

`JemBridge` se sustituye únicamente por un recolector de mensajes para representar al host Flutter. El componente MathLive, eventos, tipografía, teclas, pestañas y código `configure`/`setDraft` son los archivos reales. Las interacciones usan DOM y clics reales; no se simula la implementación del editor.

## Resultado: 6 de octubre de 2026

**16 comprobaciones aprobadas**, sin errores JavaScript ni solicitudes de recursos externos:

- Carga del editor y sus assets locales; mensaje `ready` y teclado visible.
- Pulsación de `1`, `+`, `2` produce `1+2`; Enter virtual produce un solo `submit`.
- Enter físico produce un solo `submit`.
- Host y sink editable solicitan `inputmode="none"`; tras perder y recuperar el foco, el teclado físico escribe `x+1=2` y Enter produce un solo envío.
- `C` vacía la expresión.
- La pestaña Científico permanece seleccionada al escribir y actualizar `configure`.
- Ocultar/restaurar el teclado conserva la ecuación y la pestaña seleccionada.
- Pasar por una vista de escritura de 120 px de alto y volver conserva el borrador, la pestaña y la entrada táctil.
- Una configuración que pide mostrar el teclado lo recupera incluso si MathLive lo ocultó por su cuenta.
- Las etiquetas `sin⁻¹`, `cos⁻¹` y `tan⁻¹` caben en sus teclas e insertan las funciones inversas correspondientes.
- `setDraft` desde el host no genera un evento `input` de vuelta.
- Cambio ES/EN seguido de interacción mantiene el teclado operativo.
- Teclas de la fila de cuatro columnas conservan al menos 62 px de ancho y una altura entre 44 y 50 px en tres tamaños, dejando más espacio al editor.
- Comprobación final de errores JavaScript y tráfico externo.

| Viewport del editor | Tecla medida | Ancho ocupado por cuatro teclas |
|---|---:|---:|
| 304×380 | 66×46 px | 276 px |
| 360×560 | 80×46 px | 332 px |
| 768×560 | 182×46 px | 740 px |

La altura de las teclas ya no crece con el viewport: el espacio adicional se asigna al campo de ecuación. Las pestañas Básico, Científico y Cálculo tienen además 8 px de separación horizontal; este ajuste se revisó visualmente sin cambiar las alturas del editor ni del teclado. Capturas: `output/playwright/editor-mobile.png`, `output/playwright/editor-scientific-mobile.png` y `output/playwright/editor-final.png`. Son del editor aislado, no de la interfaz Flutter completa. La validación sin red externa demuestra que no hay dependencia de CDN para estas operaciones; se sigue usando un servidor estático de loopback para cargar archivos en el navegador de prueba.

## Fallos detectados y corregidos

Antes de los ajustes, MathLive aplicaba su ancho predeterminado de `10cqw`: a 360 px las teclas solo medían 31×48 px. La primera corrección mantuvo cinco columnas; tras probarlo en el teléfono se cambió a cuatro con `--keycap-width:calc((100cqw - 24px)/4)` y etiquetas inversas abreviadas. La altura creciente hasta 64 px ocupaba demasiado espacio: ahora se mantiene en 46 px, con separación de 4 px y tipografía de 22 px. El margen exterior de Flutter también se redujo para dar más ancho al teclado. Se eliminó la barra «Jem Calc» y se reunieron historial, ajustes, RAD/DEG, Graficar y maximizar en una sola fila, respetando el área segura del sistema.

La pantalla maximizada ocultaba el teclado incluso al volver desde Escribir. Seleccionar Teclado ahora restaura la pantalla, también cuando ese modo ya estaba seleccionado. La configuración del WebView se envía después del layout de Flutter, mantiene el mismo árbol del editor y comprueba la visibilidad real de MathLive al mostrarlo. El modelo también restaura la pantalla después de reconocer tinta o foto.

La toolbar auxiliar se desactiva una sola vez con `mathVirtualKeyboard.editToolbar='none'`; quedan visibles las pestañas. El botón `C` usa el comando MathLive `deleteAll`, que vacía el contenido y emite el cambio correspondiente.

Enter físico disparaba **dos** mensajes porque lo atendían tanto `beforeinput` como `keydown`. Se conserva `beforeinput` para `insertLineBreak`; el listener adicional de Enter se eliminó. La prueba confirma un envío tanto con teclado físico como con la tecla virtual.

MathLive mantiene toolbars y teclas de otras pestañas en el DOM aunque estén ocultas. Los selectores del harness se limitan a `.MLK__layer.is-visible`. Además, las teclas con clase `action` no llevan necesariamente `.MLK__keycap`; el harness usa su `aria-label` dentro de la capa visible.

## Teclado nativo

El bundle 0.111.0 crea un sink `contenteditable` en el shadow DOM con `inputmode="none"`, pero también marca el host `<math-field>` como editable sin ese atributo. El HTML ahora declara `inputmode="none"` en el host para cubrir el foco restaurado por el WebView. Es el atributo estándar para editores que ofrecen su propio teclado; conserva la edición y la entrada física ([HTML Standard](https://html.spec.whatwg.org/multipage/interaction.html#attr-inputmode)). `mathVirtualKeyboardPolicy='manual'` controla solamente cuándo se muestra el panel de MathLive ([guía oficial](https://mathlive.io/mathfield/guides/virtual-keyboard/)).

El harness confirma atributos y escritura después de un cambio real de foco, pero Chrome en macOS no reproduce Gboard. La corrección de su apertura al volver de permisos de cámara requiere comprobar la app Android reconstruida.

## Límite de la verificación

Estas pruebas cubren Chromium con assets actuales en disco. No certifican que una compilación móvil anterior contenga esos mismos assets ni sustituyen una prueba de WebView en Android/iPad. Los cambios en assets requieren reconstruir y reinstalar la app; un hot restart puede conservar archivos empaquetados anteriores. Los errores TLS del cliente Flutter y las transiciones del contenedor nativo se prueban separadamente.
