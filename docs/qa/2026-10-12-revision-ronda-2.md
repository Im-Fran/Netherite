# Revisión completa de Netherite — ronda 2 (2026-10-12)

Revisión de los arreglos de la ronda 1 ([2026-10-11-revision-completa.md](2026-10-11-revision-completa.md)), con todo integrado en `im-fran/app-complete-review-90eb0d`.

**Estado base:** build macOS ✅, build iOS Simulator ✅, `swift test` 80/80 ✅.

**Cómo se probó**
- **En vivo, macOS:** build aislada (`cl.franciscosolis.netherite.review`), con preferencias y estado de ventanas borrados. Vault de prueba: copia de `Fixtures/SampleVault`.
- **Revisión estática:** una pasada al core y otra a la app y las extensiones, sobre el diff `0163314..HEAD`. Las pruebas del core están en una copia del paquete en el scratchpad.

**Leyenda:** 🔴 reproducido en vivo · 🧪 confirmado con prueba · 📖 confirmado leyendo el código.

## Arreglos de la ronda 1 verificados en vivo ✅

| ID | Qué se comprobó |
|---|---|
| N-01 | Después de nombrar una nota y pulsar Return, lo que se escribe llega al cuerpo |
| N-02 | Los tips ya no se comen lo que se escribe en el cuerpo (ver R2-05 para el título) |
| N-03 | Escribir rápido ya no reordena caracteres |
| N-08 | Una nota renombrada por fuera se cierra y no se recrea con el nombre viejo |
| N-11 | Una tarjeta nueva del canvas toma el foco |
| N-32 | Las tarjetas vacías se descartan |
| N-33 | El título de la ventana sale sin `.canvas` |
| N-34 | Las menciones se ven legibles, sin `[[…]]` |
| N-35 | Al abrir otra nota, el modo lectura vuelve a edición |

## Resumen

| ID | Sev. | Origen | Área | Problema |
|---|---|---|---|---|
| R2-01 | Alta | 📖 | Datos | Se ignora lo que se escribe en una nota que existe en disco pero aún no está en el índice, y después se revierte (regresión de N-08) |
| R2-02 | Alta | 📖 | Datos | Se pierde lo que se escribe mientras `index.load()` todavía no termina |
| R2-03 | Media-Alta | 🧪 | Rename | Renombrar a un nombre con `'` o `"` deja inválido el YAML de quien enlaza y se pierden todas sus propiedades |
| R2-04 | Media | 🔴 | Canvas | Se pierden caracteres al escribir en una tarjeta del canvas («Tarjeta QA» → «TareaQA») |
| R2-05 | Media | 📖 | Editor | Los tips siguen robando el foco mientras se escribe el título de una nota nueva |
| R2-06 | Media | 🔴 | Editor | La lista de `[[` sigue saliendo al fondo de la ventana (N-12 no quedó arreglado) |
| R2-07 | Media | 📖 | Inspector | El borrador de una propiedad tipo lista pasa a otra nota y sobrescribe sus valores |
| R2-08 | Media | 📖 | iOS | Después de una presentación a pantalla completa, el watcher queda apagado y `.task` se vuelve a ejecutar |
| R2-09 | Media | 🧪 | Render | `[texto](#Heading)` se rompe porque el token de tag se mete en el `href` (y hay tokens dentro de atributos en general) |
| R2-10 | Media-Baja | 📖 | Share | La Share Extension bloquea el hilo principal con `url(forUbiquityContainerIdentifier:)`, y `canReachVault` no comprueba nada |
| R2-11 | Baja-Media | 🧪 | Parser | Parsear es cuadrático en tags × links (regresión de N-36) |
| R2-12 | Baja-Media | 🧪 | Render | `sanitize` es cuadrático con muchos `<tag` sin cerrar |
| R2-13 | Baja | 📖 | Memoria | Un ciclo de retención en `RootView` filtra las `WindowState` al cerrar ventanas |
| R2-14 | Baja | 📖 | Sandbox | `AppModel.close` llama a `stop` sobre un URL estandarizado sin ámbito (N-30 incompleto) |
| R2-15 | Baja | 📖 | Datos | `trash` descarta las ediciones pendientes antes de saber si la papelera funcionó |
| R2-16 | Baja | 📖 | Audio | Un fallo al guardar la grabación al cerrar la hoja no se ve en ninguna parte |
| R2-17 | Baja | 🧪📖 | Recovery | `stableID`: lo comparten las copias de un vault, cambia en cada llamada si es de solo lectura y se regenera si `id.json` es un placeholder de iCloud |
| R2-18 | Baja | 🧪 | Vaults | `Vault.folderName` todavía acepta `. .` y `. ..` (N-43 incompleto) |
| R2-19 | Baja | 🧪 | Render | `section(of:)` elige mal la sección con U+2028 o `\r` dentro de código, frontmatter o math |
| R2-20 | Baja | 📖 | Import | El presupuesto de ZIP es por archivo y no por import; 2 GiB es demasiado para iOS |
| R2-21 | Baja | 🔴 | Vault | Abrir un vault reescribe `.netherite/recent.json` y `bookmarks.json` aunque nada haya cambiado |
| R2-22 | Baja | 📖 | CSP | `script-src` permite `nth:` y el nonce es fijo por lanzamiento, así que en un sitio publicado es público |
| R2-23 | Baja | 🔴 | iOS | El primer toque en "Omitir" del onboarding no responde (N-49, sigue abierto) |

---

## Detalle

### R2-01 · Se ignora lo que se escribe en una nota que aún no está en el índice 📖
- **Dónde:** `Netherite/App/VaultModel.swift:62,75,102`. `isGone` es `index.isLoaded && !index.files.contains(path)`, y entonces `edit`/`save` salen sin hacer nada.
- **Cómo se llega a una nota así:**
  - `WindowState+Plugins.swift:12` (`openDailyNote` solo registra la nota si el archivo no existe).
  - Deep link `open?path=` (`VaultWindow.swift:128`).
  - Spotlight (`VaultWindow.swift:67`).
  - Cualquier archivo creado por el widget, la Share Extension o un intent antes del refresco.
- **Qué pasa:** lo que se escribe se ignora. Cuando el refresco termina, `sync` aplica el texto del disco y lo escrito desaparece de la vista.
- **Fix:**
  - En `edit`, si la ruta no está en el índice pero `vault.exists(path)`, llamar a `index.didCreate(path)` y seguir.
  - Tratar la nota como borrada solo si además `!vault.exists(path)`.
  - Comprobar que el archivo existe antes de abrirlo desde `open` o Spotlight, y en Spotlight comprobar también el vault.

### R2-02 · Se pierde lo que se escribe mientras carga el índice 📖
- **Dónde:** `Packages/NetheriteCore/Sources/NetheriteCore/Index/VaultIndex.swift:51-53` (`files = …; notes = records` pisa lo editado) y `VaultWindow.swift:58-62` (la última nota se abre antes de que el índice cargue).
- **Fix:** `notes = records.merging(notes) { _, mem in mem }`, y unir `files` con lo que se creó durante la carga (el mismo patrón que `refreshFromDisk`).

### R2-03 · Renombrar con `'` o `"` deja inválido el frontmatter 🧪
- **Dónde:** `Core/Index/VaultIndex.swift:195-208`, la reescritura textual del YAML crudo.
- **Reproducción:** con `related: '[[Old]]'`, mover `Old.md` a `Mom's notes.md` deja `'[[Mom's notes]]'`, que no es YAML válido. Todas las propiedades de esa nota se pierden.
- **Fix:** reescribir los links a nivel de valor (`parsed.properties` → `Frontmatter.replacing`), o escapar según el estilo de comillas del escalar.

### R2-04 · Se pierden caracteres en una tarjeta del canvas 🔴
- **Reproducción:** doble clic en el canvas y escribir «Tarjeta QA» de corrido. Se guarda `TareaQA` (faltan la `j`, la `t` y el espacio).
- **Dónde:** `Netherite/Features/Canvas/CanvasNodeView.swift:47-52`. El `TextEditor` usa `Binding(get: { node.text }, set: { model.setText })`, y cada tecla muta el modelo y redibuja el nodo, así que el editor recibe un texto desfasado.
- **Fix:** un `@State` local para el texto mientras se edita, que se aplique al modelo con debounce o en `endEditing`.

### R2-05 · Los tips roban el foco mientras se escribe el título 📖
- **Dónde:** `WindowState.swift:190-192`. Solo mira `EditorController.isEditing`, que se refiere al cuerpo. `NoteEditorView.swift:124-130`.
- **Fix:** que `isEditing` también incluya `titleFocused`.

### R2-06 · La lista de `[[` sigue saliendo al fondo (N-12) 🔴
- **Reproducción:** escribir `Enlace a [[Wel` en la segunda línea de una nota. La lista aparece a unos 600 pt del caret, igual que antes del arreglo.
- **Pista:** el arreglo cambió de dónde sale el rect del caret (TextKit 2), pero no de dónde se posiciona el overlay. Revisar la conversión del rect a las coordenadas del overlay de SwiftUI y el origen invertido de AppKit (`isFlipped`/`convert(_:to:)`).

### R2-07 · El borrador de una propiedad tipo lista pasa a otra nota 📖
- **Dónde:** `Netherite/Features/Inspector/InspectorView.swift:321-341,46`. El `PropertiesEditor` no tiene `.id(path)`, así que el `@State draft` sobrevive al cambiar de nota.
- **Fix:** `.id(path)`.

### R2-08 · iOS: el watcher queda apagado después de una presentación a pantalla completa 📖
- **Dónde:** `VaultWindow.swift:50-64` y `fullScreenCover` (`:36`). `onDisappear` marca la ventana como en segundo plano y nada vuelve a encender el watcher. Además, `.task` se vuelve a ejecutar y salta a la nota diaria.
- **Fix:** en `onAppear`, volver a marcar la ventana en primer plano, y proteger `.task` con un flag `started`.

### R2-09 · Tokens dentro de atributos en el render 🧪
- **Dónde:** `Core/Render/HTMLRenderer.swift:90-93`.
- **Reproducción:** `[Jump](#Intro)` produce `href="nth://note/<a class="tag" …>#Intro</a>#"`. Rompe los índices tipo GitHub. `![alt $x$](…)` mete un `<span>` dentro de `alt`.
- **Fix:**
  - Marcar como ocupados los rangos de `mdLink` antes de añadir tags.
  - Quitar los marcadores de `dest`/`plainText` en `visitLink`/`visitImage`.

### R2-10 · La Share Extension bloquea el hilo principal 📖
- **Dónde:** `ShareExtension/ShareViewController.swift:35`. `canReachVault` llama a `withVault` en el inicializador, en el hilo principal, y `withVault { _ in true }` no toca la carpeta.
- **Fix:** calcularlo fuera del hilo principal y comprobar que la carpeta se puede leer (`isReadableFile`).

### R2-11 · Parsear es cuadrático en tags × links 🧪
- **Dónde:** `Core/Markdown/NoteParser.swift:119`.
- **Medición:** 10 000 repeticiones de `[[x]] #t ` tardan 0,9 s en release.
- **Fix:** un `IndexSet` con los rangos de los links y `intersects(integersIn:)`.

### R2-12 · `sanitize` es cuadrático 🧪
- **Dónde:** `Core/Render/HTMLRenderer.swift`, unas líneas 270-292.
- **Medición:** `"<div>\n" + "<a " × 10 000` tarda 1,2 s en release.
- **Fix:** si no hay `>` desde `j`, emitir el resto escapado y terminar.

### R2-13 · Ciclo de retención en `RootView` 📖
- **Dónde:** `NetheriteApp.swift:117-118`. `closeVault` y `switchVault` capturan `self`, que retiene la `WindowState`.
- **Fix:** capturar solo los bindings (`$vaultPath`, `$pendingLink`).

### R2-14 · `close` no libera el acceso security-scoped 📖
- **Dónde:** `AppModel.swift:190`. `stop` se llama sobre `vault.root`, que es un URL estandarizado y no lleva el ámbito.
- **Fix:** guardar el URL exacto (`scoped: [String: URL]`).

### R2-15 · `trash` descarta las ediciones antes de tiempo 📖
- **Dónde:** `VaultModel.swift:175-176`.
- **Fix:** guardar antes de mover a la papelera, o limpiar `dirty` solo si la papelera funcionó.

### R2-16 · Un fallo al guardar la grabación no se ve 📖
- **Dónde:** `AudioRecorder.swift:143-146,160-165`. En la ruta de `onDisappear` no se limpia `lastError`, así que el error queda en una hoja que ya se cerró.
- **Fix:** dejar que aparezca la alerta de la ventana.

### R2-17 · Problemas de `stableID` 🧪📖
- **Dónde:** `Core/Vault/VaultSettings.swift:84-90`.
- **Qué pasa:**
  - Al copiar un vault, la copia tiene el mismo ID y File Recovery mezcla las snapshots de ambos.
  - En un vault de solo lectura se genera un ID nuevo en cada llamada.
  - Si `id.json` es un placeholder de iCloud, se genera un ID nuevo y se sincroniza.
- **Fix:**
  - Guardar la ruta junto al ID y regenerarlo si no coincide.
  - Usar como fallback el hash de la ruta.
  - No escribir el ID si existe `.id.json.icloud`.

### R2-18 · `folderName` acepta `. .` 🧪
- **Dónde:** `Core/Vault/VaultSettings.swift:93-97`.
- **Fix:** repetir trim y drop hasta que el nombre no cambie, o rechazar cualquier nombre que empiece con `.`.

### R2-19 · `section(of:)` se desalinea con U+2028 o `\r` 🧪
- **Dónde:** `NoteParser.blank` (`NoteParser.swift:169`) convierte `\r` y U+2028 en espacios.
- **Fix:** preservarlos igual que `\n`.

### R2-20 · El presupuesto de ZIP es por archivo 📖
- **Dónde:** `Core/Import/Importers.swift:54`.
- **Fix:** un presupuesto compartido en `Importer.files(at:)`, y un tope más bajo en iOS (512 MB).

### R2-21 · Abrir un vault reescribe metadatos 🔴
- **Visto:** al abrir un vault, la app reescribe `.netherite/recent.json` y `bookmarks.json`, y crea `id.json`, aunque nada haya cambiado. En iCloud eso genera sincronizaciones y conflictos innecesarios.
- **Fix:** escribir solo cuando el contenido cambie. Por ejemplo, que `saveConfig` compare con lo que ya está en disco.

### R2-22 · CSP con `nth:` en `script-src` y nonce fijo 📖
- **Fix:**
  - Limitar `script-src` a `nth://web/` (los assets de la app), o a `'self'` en el sitio publicado.
  - En el sitio publicado, usar hashes o un nonce por export.

### R2-23 · El onboarding de iOS no responde al primer toque en "Omitir" 🔴
- **Hipótesis:** el `.gesture(DragGesture)` de la raíz de `OnboardingView` se adelanta al botón; probar con `.simultaneousGesture`. También puede ser que el `fullScreenCover` aparezca mientras `RootView` cambia el vault o el esquema de color.
