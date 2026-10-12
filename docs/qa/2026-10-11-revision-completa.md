# Revisión completa de Netherite — 2026-10-11

Rama `im-fran/app-complete-review-90eb0d` (base `68791a4`, versión 0.1.1+13).

**Estado base:** build macOS ✅, build iOS Simulator ✅, `swift test` 53/53 ✅.

**Cómo se probó**
- **En vivo, macOS:** build Debug relanzada con otro bundle id (`cl.franciscosolis.netherite.review`) para no compartir preferencias con la app instalada. Vault de prueba: copia de `Fixtures/SampleVault`.
- **En vivo, iOS:** iPhone 17 (simulador), con el onboarding y la guía.
- **Revisión estática:** tres pasadas sobre `NetheriteCore`, editor/workspace y ajustes/import/extensiones. 13 de los hallazgos del core se confirmaron con programas de prueba.

**Leyenda**
- **Origen:** 🔴 reproducido en vivo · 🧪 confirmado con prueba · 📖 confirmado leyendo el código (el efecto en runtime depende de AppKit/SwiftUI).
- Las rutas son relativas a la raíz del repo; `Core/` = `Packages/NetheriteCore/Sources/NetheriteCore/`.

---

## Resumen

| ID | Sev. | Origen | Área | Problema |
|---|---|---|---|---|
| N-01 | Alta | 🔴 | Editor | Tras nombrar una nota nueva y pulsar Return, lo que se escribe se pierde |
| N-02 | Alta | 🔴 | Editor | Los tips (TipKit) roban el foco del teclado y se pierde lo que se escribe |
| N-03 | Alta | 🔴 | Editor macOS | El caret retrocede una posición al empezar a escribir: caracteres fuera de orden o perdidos |
| N-04 | Alta | 🧪📖 | Seguridad | Path traversal: `Vault.url(for:)` no confina rutas (zip-slip, deep link, Atajos, `nth://`) |
| N-05 | Alta | 🧪 | Seguridad | XSS: links `javascript:` y un `sanitize` por regex que se puede saltar |
| N-06 | Alta | 📖 | Seguridad | El Web Viewer expone `nth://vault` a cualquier web (`ACAO: *`) |
| N-07 | Alta | 🧪 | Datos | Editar una propiedad destruye otras del frontmatter |
| N-08 | Alta | 🔴📖 | Datos | Una nota renombrada/borrada fuera de la ventana sigue abierta; al escribir se recrea con la ruta vieja |
| N-09 | Alta | 📖 | Extensiones | Un vault enviado a la papelera sigue siendo el `SharedVault`: los clips y widgets escriben ahí |
| N-10 | Media-Alta | 📖 | Extensiones | La Share Extension y los widgets no acceden a vaults locales ni (probablemente) a iCloud |
| N-11 | Media | 🔴 | Canvas | Una tarjeta nueva no recibe foco: el texto va al explorador y la tarjeta queda vacía |
| N-12 | Media | 🔴 | Editor | El autocompletado de `[[` aparece al fondo de la ventana, lejos del caret |
| N-13 | Media | 📖 | Editor macOS | El undo de NSTextView queda desfasado cuando el texto se reemplaza por código |
| N-14 | Media | 📖 | Canvas | Si la lectura falla, se muestra un canvas vacío que pisa el archivo real al editar |
| N-15 | Media | 📖 | Datos | Salir con ⌘Q puede perder los últimos ~700 ms de edición |
| N-16 | Media | 🧪 | Rename | Renombrar no actualiza los links del frontmatter |
| N-17 | Media | 🧪 | Rename | Renombrar rompe tablas (`\|` del alias) |
| N-18 | Media | 🧪 | Rename | Renombrar rompe los links de la nota a sí misma |
| N-19 | Media | 🧪 | Parser | Un backtick suelto oculta links y tags de varios párrafos |
| N-20 | Media | 🧪 | Render | Crash al embeber un bloque o heading en notas con `\r` o U+2028 |
| N-21 | Media | 🧪 | Render | Crash e inyección vía los marcadores internos U+E000/U+E001 |
| N-22 | Media | 📖 | Título | El título puede contener saltos de línea, que acaban en el nombre del archivo |
| N-23 | Media | 📖 | Vault | Una ventana en background apaga el watcher para todas las ventanas del vault |
| N-24 | Media | 📖 | Inspector | En una propiedad tipo lista no se puede escribir una coma |
| N-25 | Media | 📖 | Lectura | El modo lectura ignora el salto a encabezado |
| N-26 | Media | 📖 | Canvas | El undo del canvas sigue vivo después de salir del canvas |
| N-27 | Media | 📖 | Memoria | `BlockRenderer.shared`: caché sin límite y vault compartido entre ventanas |
| N-28 | Media | 📖 | Widgets | Widgets y sugerencias de Atajos desactualizados o con mezcla de vaults |
| N-29 | Media | 📖 | Widgets | Los deep links del widget no indican el vault |
| N-30 | Media | 📖 | Sandbox | Security-scoped: falta `stop` en `close()`; el export no resuelve el bookmark |
| N-31 | Media | 📖 | Audio | La grabación se corta en background y se borra al cerrar la hoja |
| N-32 | Baja | 🔴 | Canvas | Las tarjetas vacías se guardan en el `.canvas` |
| N-33 | Baja | 🔴 | UI | El título de la ventana muestra `Board.canvas` mientras la barra lateral muestra `Board` |
| N-34 | Baja | 🔴 | Inspector | El contexto de las menciones muestra wikilinks crudos (`[[Empieza aquí]]`) |
| N-35 | Baja | 🔴 | Lectura | El modo lectura se mantiene al cambiar de nota y escribir parece no hacer nada |
| N-36 | Baja | 🧪 | Parser | Aparecen tags falsos desde links a headings (`[[#Intro]]` → `#Intro`) |
| N-37 | Baja | 🧪 | Parser | El heading `# C#` se lee como "C" |
| N-38 | Baja | 📖 | Import | Un ZIP malicioso puede crashear la app o agotar la memoria |
| N-39 | Baja | 📖 | CLI | `netherite publish` sube archivos viejos o ajenos y borra `assets/` |
| N-40 | Baja | 🧪 | Render | El render es cuadrático con muchos links |
| N-41 | Baja | 📖 | Recientes | Los recientes no se actualizan tras mover o enviar a la papelera |
| N-42 | Baja | 📖 | Explorador | Se puede arrastrar una carpeta a un descendiente suyo y se acepta texto externo como ruta |
| N-43 | Baja | 📖 | Vaults | Crear un vault no valida el nombre (`..`, `/`, ya existente) |
| N-44 | Baja | 📖 | iPhone | La hoja de Workspaces tiene `minWidth: 440` |
| N-45 | Baja | 📖 | Temas | "Create Theme from Current…" sobrescribe el tema custom sin avisar |
| N-46 | Baja | 📖 | Recovery | Las snapshots de File Recovery quedan huérfanas al mover el vault |
| N-47 | Baja | 📖 | Publish | Publish deja carpetas `netherite-site-*` en tmp |
| N-48 | Baja | 📖 | Bases | `toFixed` crashea con `NaN`/1e20, y `BaseFile` pierde claves al guardar |
| N-49 | Baja | 🔴 | iOS | El primer toque en "Omitir" del onboarding no responde |

---

## Alta

### N-01 · Tras nombrar una nota nueva y pulsar Return, lo que se escribe se pierde 🔴
- **Dónde:** `Netherite/Features/Editor/NoteEditorView.swift:138`, en `.onSubmit { commitTitle(); controller.focus() }`.
- **Reproducir (macOS):**
  1. Archivo › Nueva nota.
  2. Escribe "Prueba QA" y pulsa Return.
  3. Escribe "Hola mundo". No aparece nada y el `.md` queda con 0 bytes. Se reprodujo dos veces, en la guía y en el vault de prueba.
- **Causa probable:** `commitTitle()` renombra el archivo, así que el editor se recrea con el `path` nuevo. Entonces `controller.focus()` hace `makeFirstResponder` sobre el text view viejo, que ya se va a descartar. La ventana queda sin first responder.
- **Fix:** guardar el pedido de foco en el estado de la ventana, igual que `window.freshNote` (por ejemplo `window.focusBody = newPath`), y consumirlo en `onAppear` del editor nuevo. Otra opción: llamar a `focus()` en el siguiente turno, cuando el text view nuevo ya esté montado.

### N-02 · Los tips (TipKit) roban el foco del teclado y se pierde lo que se escribe 🔴
- **Qué pasa:** al empezar a usar un vault aparecen popovers en cadena ("Vista de lectura", "Salta a cualquier nota", "Mira qué enlaza aquí", "Explora el grafo", "Todas las acciones…", "Muévete por el grafo", "Piensa en un lienzo"). Mientras alguno está visible, lo que se escribe en el editor no llega: se perdió una frase completa. Además, cada popover tapa controles de la barra.
- **Fix:** mostrar los tips con `TipView` inline o con `.popoverTip` sin hacerlos key. No encadenar un tip nuevo mientras el editor tenga foco; usar `Tips.MaxDisplayCount`/`displayFrequency` o mostrarlos solo cuando el usuario esté inactivo.

### N-03 · El caret retrocede una posición al empezar a escribir 🔴
- **Reproducir:**
  1. En una nota, escribe de corrido `AAAA BBBB … PPPP`.
  2. Resultado: `AAA BBBB … PPPPA`. El 4.º carácter queda detrás del caret y "viaja" al final de todo lo escrito después, incluso en líneas nuevas.
  3. En otras ráfagas se perdieron caracteres (`Enlace` → `Enlce`, `test fin` → `ts fn` con una `i` suelta al final del documento).
  4. Escribiendo con ~80 ms entre teclas no ocurre.
- **Causa probable:** `MarkdownTextView.updateNSView` (`Netherite/Features/Editor/MarkdownTextView.swift:430-434`) reasigna `tv.string = text` con un `text` del binding desfasado, y restaura una selección vieja mientras la escritura sigue en curso.
- **Fix:** no reasignar el string si el cambio viene del propio text view (flag `isEditing`/versión), y aplicar solo diferencias con `replaceCharacters`. Esto también resuelve N-13.
- **Nota:** se reprodujo con eventos de teclado sintéticos y rápidos. Falta confirmarlo con un tecleo humano rápido, pero la pérdida de `Enlce` ocurrió en la primera palabra.

### N-04 · Path traversal: `Vault.url(for:)` no confina rutas 🧪
- **Causa raíz:** `Core/Vault/Vault.swift:13-15` hace `root.appending(path:)` sin normalizar ni comprobar que el resultado siga dentro de `root`.
- **Entradas:**
  - Import de ZIP: `Core/Import/Importers.swift:238,244,270,280-282` y `Core/Import/ZipReader.swift:58-61`. Probado: una entrada `../../escaped/pwn.md` se escribe fuera del vault. `attachment(keepFolder:)` acepta cualquier extensión; en el build Direct (sin sandbox) sirve para dejar un LaunchAgent.
  - Deep link `netherite://new?name=../../x`: `Netherite/Features/Workspace/VaultWindow.swift:121-122`.
  - `CreateNoteIntent` con `folder: "../.."`: `Netherite/Intents/NoteIntents.swift:51-55`.
  - Lectura con `nth://vault/..%2F..`: `Netherite/Features/Reader/HTMLWebView.swift:17`.
- **Fix:** en `url(for:)`, aplicar `standardizedFileURL` y exigir el prefijo de `root`; si no, lanzar un error. Además, descartar los componentes `..`, `.` y absolutos en `ZipReader`/`Writer.folderPath`. Añadir un test.

### N-05 · XSS en el render 🧪
- **Links:** `[x](javascript:alert(1))` produce `href="javascript:…"` (`Core/Render/HTMLRenderer.swift:281-283`; también en `visitImage`, línea 295).
- **Sanitize:** `sanitize` (`HTMLRenderer.swift:202-207`) es un regex que se puede saltar:
  - `<img src=x/onerror=…>`
  - `jav&#x61;script:`
  - `<form action="javascript:…">`
- **Alcance:** el WKWebView de la app y los sitios publicados.
- **Fix:**
  - Permitir solo los esquemas `http`, `https`, `mailto`, `obsidian`, `netherite` y anclas.
  - Sanitizar con una lista de tags y atributos permitidos sobre un DOM parseado.
  - Añadir CSP al HTML de la app y del sitio publicado.

### N-06 · El Web Viewer expone `nth://vault` a cualquier web 📖
- **Dónde:** `Netherite/Features/Reader/HTMLWebView.swift:7-26,148`, usado por `Netherite/Features/Plugins/WebViewer.swift:50`.
- **Qué pasa:** el handler responde con `Access-Control-Allow-Origin: *`. Una web puede hacer `fetch('nth://vault/.netherite/recent.json')` y leer notas, o navegar a `nth://new/…` y crear notas. Además, `WindowState+Plugins.swift:126-130` acepta `file://` y `nth://` en la barra de direcciones.
- **Fix:**
  - No registrar el handler de vault cuando `url != nil`.
  - Rechazar las peticiones cuyo `mainDocumentURL` no sea `nth://`.
  - Quitar `ACAO: *`.
  - Limitar la barra de direcciones a http/https.

### N-07 · Editar una propiedad destruye otras del frontmatter 🧪
- **Dónde:** `Core/Markdown/Frontmatter.swift:77-92,118-128`, que se llama en cada edición desde `InspectorView.swift:316` y `BaseView.swift:414`.
- **Probado:** al editar cualquier propiedad, el resto del bloque cambia así:

  | Antes | Después |
  |---|---|
  | `authors: [{name: Ana}]` | `[]` |
  | `meta: {rating: 5}` | el string `'rating: 5\n'` |
  | `version: 1.10` | `1.1` |
  | `zip: 01234` | `668` (octal) |
  | `answer: no` | `false` |

- **Fix:** reemplazar solo la clave editada en el YAML original, conservar el escalar crudo de las claves que no se tocaron y usar la semántica de YAML 1.2.

### N-08 · Una nota renombrada/borrada fuera de la ventana sigue abierta y se recrea con la ruta vieja 🔴📖
- **Visto en vivo:** se borró `Prueba QA.md` desde fuera. El explorador se actualizó, pero el editor y la pestaña siguieron mostrando "Prueba QA".
- **Por código:**
  - `WindowState.swift:257-269`: rename/move/trash solo remapean los paneles de la ventana actual.
  - `VaultModel.swift:46-48`: `text(of:)` devuelve `""`.
  - `VaultModel.swift:62-64`: `save` sale en silencio y la nota queda `dirty` para siempre.
  - `VaultIndex.swift:89-93`: `refreshFromDisk` elimina la nota aunque tenga ediciones pendientes.
  - Resultado: si se escribe, el archivo se recrea con la ruta vieja y solo con lo nuevo.
- **Reproducir:** ⌘⌥N abre una segunda ventana con la misma nota; renómbrala en la ventana A; en la ventana B la nota aparece vacía.
- **Fix:**
  - Remapear o eliminar las rutas a nivel de `VaultModel` y aplicarlo en todas las `WindowState`.
  - Hacer que `edit`/`save` no escriban rutas que ya no están en `index.files`.
  - Avisar del conflicto cuando la nota esté `dirty`.

### N-09 · Un vault enviado a la papelera sigue siendo el `SharedVault` 📖
- **Dónde:** `Netherite/App/AppModel.swift:171-188` (`trashVault`) y `SharedVault.swift:53-58`. El bookmark sigue al vault hasta `.netherite-trash/`.
- **Consecuencia:** los clips de la Share Extension y el "Log Time" del widget se guardan en el vault borrado, que se purga a los 90 días.
- **Fix:** en `trashVault`/`forget`/`close`, si `SharedVault.current()` es ese vault, publicar el siguiente reciente o limpiarlo, y llamar a `reloadAllTimelines`.

### N-10 · La Share Extension y los widgets no acceden a vaults locales ni (probablemente) a iCloud 📖
- **Vaults locales:** viven en `URL.documentsDirectory` de la app (`AppModel.swift:65`), al que las extensiones no tienen acceso.
- **Vaults en iCloud:** ninguna extensión llama a `url(forUbiquityContainerIdentifier:)`. Ver `ShareViewController.swift:32` y `NetheriteWidgets.swift:43-44`.
- **Síntoma:** "Open a vault in Netherite first", o un error de escritura.
- **Fix:** llamar a `url(forUbiquityContainerIdentifier:)` en las extensiones, y crear los vaults locales en el contenedor del App Group (o mostrar un mensaje específico).
- **Pendiente:** verificarlo en un dispositivo.

## Media

### N-11 · Una tarjeta nueva del canvas no recibe foco 🔴
- **Reproducir:** doble clic en un espacio vacío del canvas y escribir "Tarjeta QA". La tarjeta se crea vacía y la selección de la barra lateral salta a "Templates": el type-select del `List` se llevó las teclas.
- **Dónde:** `Netherite/Features/Canvas/CanvasNodeView.swift:47-52`. El `TextEditor` en modo edición no tiene `@FocusState`.
- **Fix:** `@FocusState`, con `.focused($focused)` y `onAppear { focused = true }` cuando `editing`.

### N-12 · El autocompletado de `[[` aparece al fondo de la ventana 🔴
- **Qué pasa:** al escribir `[[Wel` en la primera línea, la lista de sugerencias sale abajo, a unos 600 pt del caret.
- **Fix:** anclarla al rect del caret (`firstRect(forCharacterRange:)`).

### N-13 · El undo de NSTextView queda desfasado cuando el texto se reemplaza por código 📖
- **Dónde:** `MarkdownTextView.swift:430-434`.
- **Qué lo dispara:** editar una propiedad inline, marcar tareas en lectura, Bases, cambios externos o la misma nota en dos paneles. Después de eso, ⌘Z deshace en offsets viejos (corrompe la nota) o lanza `NSRangeException`. El caret también salta.
- **Fix:** el mismo de N-03 (aplicar diferencias con `shouldChangeText`/`replaceCharacters`/`didChangeText`), o `undoManager.removeAllActions(withTarget:)`.

### N-14 · Si la lectura falla, se muestra un canvas vacío que pisa el archivo real 📖
- **Dónde:** `Netherite/Features/Canvas/CanvasModel.swift:45` hace `(try? vault.read(path)) ?? ""`.
- **Qué pasa:** con un placeholder de iCloud o un error de coordinación, el canvas se ve vacío, y la primera edición reemplaza el `.canvas` real. Con `loadError` (JSON inválido) también se puede editar y guardar.
- **Fix:** propagar el error como `loadError` y bloquear `save`/`mutate` mientras exista.

### N-15 · Salir con ⌘Q puede perder los últimos ~700 ms de edición 📖
- **Qué pasa:** el autosave tiene debounce (`VaultModel.swift:55-59` y `CanvasModel.swift:67-71`) y no hay `applicationWillTerminate`.
- **Fix:** un `NSApplicationDelegateAdaptor` que haga `flushAll()` de todos los modelos y canvas abiertos.
- **Pendiente:** no se reprodujo en vivo, porque el entorno bloquea ⌘Q.

### N-16 · Renombrar no actualiza los links del frontmatter 🧪
- **Dónde:** `Core/Index/VaultIndex.swift:192` y `Core/Markdown/NoteParser.swift:101-108`.
- **Qué pasa:** los links de propiedades se guardan con `range = NSNotFound` y el renombrado los salta. Con `related: "[[Old]]"`, el link queda roto.

### N-17 · Renombrar rompe tablas 🧪
- **Dónde:** `Core/Index/VaultIndex.swift:196` y `Core/Markdown/NoteParser.swift:83`.
- **Qué pasa:** la celda `| [[Old\|alias]] |` se reescribe como `[[New|alias]]` sin escapar, lo que parte la columna. Fix: recordar el separador escapado.

### N-18 · Renombrar rompe los links de la nota a sí misma 🧪
- **Dónde:** `Core/Index/VaultIndex.swift:158,226`.
- **Qué pasa:** `[[Old#Old]]` dentro de `Old.md` queda roto, porque la nota movida no entra en la lista de notas a reescribir.

### N-19 · Un backtick suelto oculta links y tags de varios párrafos 🧪
- **Dónde:** `Core/Markdown/NoteParser.swift:205`. El mismo regex está en `maskCode` y `FormatConverter`.
- **Qué pasa:** el regex `inlineCode` cruza párrafos. Se pierden backlinks y el renombrado no reescribe esos links.
- **Fix:** que un code span no cruce líneas en blanco.

### N-20 · Crash al embeber un bloque o heading 🧪
- **Dónde:** `Core/Render/HTMLRenderer.swift:169-181`.
- **Qué pasa:** `section(of:)` divide con `"\n"`, pero los números de línea vienen de `enumerateLines` (que también corta en `\r` y U+2028). Resultado: `Index out of range`.

### N-21 · Crash e inyección vía los marcadores internos 🧪
- **Dónde:** `Core/Render/HTMLRenderer.swift:115-128`.
- **Qué pasa:** `tokens[Int(...)!]` no se valida. El texto `\u{E000}7\u{E001}` en una nota provoca un crash.
- **Fix:** un nonce por render, validar el índice y escapar U+E000/U+E001 de la entrada.

### N-22 · El título puede contener saltos de línea 📖🔴
- **Dónde:** `NoteEditorView.swift:134` (`TextField(axis: .vertical)`), `:159` y `VaultModel.swift:119`. Solo se recorta `.whitespaces`.
- **Qué pasa:** en iOS, Return inserta `\n`; en macOS se puede pegar texto multilínea. En vivo, un `\n` insertado por accesibilidad quedó dentro del título. El resultado es un archivo `"Nombre\n.md"`.
- **Fix:** recortar con `.whitespacesAndNewlines` y quitar `\n`/`\r` en `rename`.

### N-23 · Una ventana en background apaga el watcher para todas 📖
- **Dónde:** `VaultWindow.swift:50-56` y `VaultModel.swift:84-91`.
- **Fix:** contar las ventanas activas por modelo, o hacerlo a nivel de app.

### N-24 · En una propiedad tipo lista no se puede escribir una coma 📖
- **Dónde:** `Netherite/Features/Inspector/InspectorView.swift:268-271`. Cada tecla hace `split(",")`.
- **Fix:** un `@State` local que haga commit al enviar o al perder el foco.

### N-25 · El modo lectura ignora el salto a encabezado 📖
- **Dónde:** `NoteEditorView.swift:32-34,164-168` frente a `ReaderView.swift:16`.
- **Fix:** en `jumpIfNeeded`, `guard !pane.reading`, o que el lector consuma `pendingLine`.

### N-26 · El undo del canvas sigue vivo después de salir 📖
- **Dónde:** `CanvasModel.swift:97-107` y `CanvasEditor.swift:22-24`.
- **Fix:** en `onDisappear`, `undoManager?.removeAllActions(withTarget: model)`.

### N-27 · `BlockRenderer.shared`: caché sin límite y vault compartido 📖
- **Dónde:** `Netherite/Features/Editor/BlockRenderer.swift:23,31-34,91`.
- **Fix:** usar `NSCache` con límites y pasar el vault en cada `Job`.

### N-28 · Widgets y Atajos desactualizados o con mezcla de vaults 📖
- **Dónde:** `ShareViewController.swift:93-124`, `NoteIntents.swift:39-40,53-84` y `AppModel.swift:303-306`.
- **Qué pasa:** después de escribir no se llama a `reloadAllTimelines`, y los recientes no están ligados a un vault.

### N-29 · Los deep links del widget no indican el vault 📖
- **Dónde:** `NetheriteApp.swift:72-79`, `VaultWindow.swift:117-124` y `SharedVault.openURL`.
- **Fix:** añadir `vault=<path>` al URL y enrutar con `app.model(forPath:)`.

### N-30 · Problemas de security-scoped 📖
- **Dónde:**
  - `AppModel.swift:125/165-168`: `close()` nunca llama a `stop`.
  - `SettingsView.swift:381-383`: "Export Vault…" no resuelve el bookmark.
  - `NetheriteWidgets.swift:44` y `ShareViewController.swift:32`: usan `resolve()` sin `stop`.

### N-31 · La grabación de audio se corta o se borra 📖
- **Dónde:** `AudioRecorder.swift:27-47,131`.
- **Qué falta:** el modo de fondo `audio` y el manejo de interrupciones.
- **Además:** `onDisappear { rec.cancel() }` borra la grabación al cerrar la hoja o la ventana.

## Baja

- **N-32 🔴** — Las tarjetas vacías del canvas se guardan en el `.canvas` (`{"type":"text","text":""}`).
  - **Fix:** descartarlas en `endEditing` si el texto está vacío.
- **N-33 🔴** — El título de la ventana y la pestaña muestran `Board.canvas`, mientras la barra lateral muestra `Board`. Contradice la entrada del CHANGELOG 0.1.1.
- **N-34 🔴** — El contexto de "Menciones enlazadas" muestra wikilinks crudos (`Volver a [[Empieza aquí]]`, `Links to [[Welcome]] and [[Missing note]]`).
- **N-35 🔴** — El modo lectura (⌘E) se mantiene al abrir otra nota en el mismo panel, y escribir parece no hacer nada. Si es intencional, falta una indicación más clara.
- **N-36 🧪** — Tags falsos desde links a headings: `[[#Intro]]` y `[x](#Other)` (`NoteParser.swift:197`).
- **N-37 🧪** — El heading `# C#` se lee como "C" (`NoteParser.swift:198`). Rompe `[[Nota#C#]]`.
- **N-38 📖** — ZIP malicioso (`ZipReader.swift:82-93,100`):
  - `baseAddress!` sobre una entrada vacía.
  - `Data(count:)` con el tamaño de la cabecera, sin tope.
  - Recursión sin límite en ZIPs anidados.
- **N-39 📖** — El CLI `netherite publish --out X` (`SiteExporter.swift:41`, `CloudflarePagesDeployer.swift:38-50`, `netherite/Netherite.swift:113`):
  - Sube páginas viejas o ajenas.
  - Borra `X/assets` del usuario.
- **N-40 🧪** — El render es cuadrático en el número de links (`HTMLRenderer.swift:64-68`): 8000 links tardan ~1 s.
- **N-41 📖** — Los recientes no se actualizan tras mover una carpeta ni tras enviar a la papelera (`VaultModel.swift:138,146`).
- **N-42 📖** — En el explorador (`FileExplorer.swift:43-45,90-91`):
  - Se puede soltar una carpeta dentro de un descendiente suyo.
  - Se acepta cualquier texto externo como ruta.
- **N-43 📖** — Crear un vault no valida el nombre (`VaultPicker.swift:307-314`, `AppModel.swift:69-70`):
  - Un nombre ya existente abre el vault existente.
  - `a/b` crea un vault anidado.
  - `..` abre como vault la carpeta de iCloud Documents.
- **N-44 📖** — `Workspaces.swift:89`: `minWidth: 440` incondicional, más ancho que un iPhone.
- **N-45 📖** — `AppearanceSettings.swift:73-79`: "Create Theme from Current…" pisa `<tono> Custom.json`.
- **N-46 📖** — File Recovery (`FileRecovery.swift:9-12,34`):
  - La clave es el SHA de la ruta absoluta, así que las snapshots quedan huérfanas al mover el vault.
  - Dos guardados en el mismo segundo se pisan.
- **N-47 📖** — `PublishView.swift:132-134,162-171`: nunca se borran las carpetas `netherite-site-*` de tmp.
- **N-48 📖** — Bases:
  - `BaseExpression.swift:297` (`toFixed`) crashea con `NaN`/1e20.
  - `BaseFile.parse` descarta claves de `properties` y fórmulas no-string al guardar.
  - `SiteExporter` sobrescribe las notas raíz `index.md`/`404.md`/`graph.md`.
- **N-49 🔴** — iOS: el primer toque en "Omitir" del onboarding no responde, porque el layout aún se está acomodando. Hay que tocar dos veces.

---

## Revisado sin hallazgos
- **Localización:** los 6 `.xcstrings` y `Settings.bundle` tienen `es` completo, sin claves `stale`.
- **App Group y entitlements:** coherentes entre la app, las extensiones y los targets App Store/Direct.
- **OpenUpdater:** verifica la firma Ed25519, el requisito de firma y la versión. La galería de templates usa HTTPS y nombres saneados.
- **Ciclos de retención:** con `WKScriptMessageHandler` están resueltos con `WeakHandler`. El monitor de scroll del canvas se limpia bien.
- **En vivo:** el modo lectura (callouts, KaTeX, Mermaid, tareas, propiedades), la paleta de comandos y la vista de grafo funcionan.

## Orden sugerido de reparación
1. **Pérdida de texto al escribir:** N-01, N-02, N-03/N-13. Son lo primero que nota cualquier usuario.
2. **Seguridad:** N-04, N-05, N-06.
3. **Integridad de datos:** N-07, N-08, N-14, N-15, N-16 a N-19.
4. **Extensiones y widgets:** N-09, N-10, N-28 a N-31.
5. Lo demás.
