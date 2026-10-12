# Revisión de Netherite — ronda 5 (2026-10-12)

Revisión de los arreglos de la ronda 4 ([2026-10-12-revision-ronda-4.md](2026-10-12-revision-ronda-4.md)) y de áreas que aún no se habían revisado a fondo: canvas JSON, grafo, plugins, Publish, Ajustes, temas, Inspector, accesibilidad y localización.

**Estado base:** build macOS ✅, build iOS Simulator ✅, `swift test` 108/108 ✅.

**Cómo se probó**
- **En vivo, macOS:** build aislada sobre un vault de prueba. Sin permiso de control de pantalla, solo se probó en segundo plano; el grafo funciona.
- **Revisión estática:** core y app.

**Leyenda:** 🧪 confirmado con prueba · 📖 confirmado leyendo el código.

## Sigue pendiente de verificar en vivo (requiere teclear de verdad)
- **R2-04:** tarjetas del canvas sin caracteres perdidos.
- **R2-05:** tips mientras se escribe el título.
- **R2-06:** posición de la lista de `[[`.

## Revisado sin hallazgos
- **Canvas JSON:** el roundtrip conserva los campos desconocidos.
- **Grafo, plugins, Slides, Web Viewer, Meeting notes y Workspaces:** sin problemas.
- **Localización:** 0 claves sin `es` y 0 strings hardcodeados.
- **Accesibilidad:** los botones de solo icono tienen labels y Dynamic Type se usa bien.
- **Fixes de la ronda 4:** sin regresiones graves en la app.

## Resumen

| ID | Sev. | Origen | Área | Problema |
|---|---|---|---|---|
| R5-07 | Media-Alta | 🧪 | Datos | Si el YAML es inválido (p. ej. `title: Meeting: Q3`), agregar o editar una propiedad borra todo el frontmatter; una clave con `: ` también rompe el YAML |
| R5-01 | Media | 🧪 | Import | Los links con ruta completa se rompen si una carpeta tiene `#`, `[`, `]`, `\|` o `^` (regresión de R4-04) |
| R5-02 | Media | 🧪 | Import | El escape de `HTMLToMarkdown` deja pasar `---` setext, `~~~`, `%%…%%` y `$…$` |
| R5-03 | Media | 🧪 | Publish (privacidad) | Los `%%comentarios%%` quedan expuestos en `search.json` del sitio publicado |
| R5-08 | Media | 📖 | Datos | Las notas cuyo nombre empieza con `.` (nueva, rename, Web Viewer, extraer, seguir un link, intent, formato de nota diaria vacío) quedan ocultas y desaparecen al refrescar |
| R5-09 | Media-Baja | 📖 | Sync | La configuración del vault (`app.json`, `bookmarks.json`, temas) no se recarga, y escribirla pisa los cambios de otro dispositivo |
| R5-04 | Baja | 🧪 | Búsqueda | `task-todo:` y `task-done:` ignoran el estado, y las tareas de listas numeradas nunca coinciden |
| R5-10 | Baja | 📖 | Vaults | "Move to iCloud Drive": lo que se escribe durante el move recrea el vault en la ruta vieja, y Ajustes muestra "Vault Not Found" |
| R5-11 | Baja-Media | 📖 | Lectura | En vista de lectura `pendingLine` nunca se consume, cada cambio recarga la página y salta, y las notas al pie no navegan |
| R5-05 | Baja | 🧪 | Render | Se pierde un `==resaltado==` después de un link cuyo título contiene `==` |
| R5-06 | Baja | 🧪 | Render | Un tag dentro del texto de un link Markdown genera `<a>` anidados y se indexa |
| R5-12 | Baja | 📖 | Localización | Faltan plurales en `%lld days`, `%lld days remaining`, `Added %lld templates.`, `%lld attendees` y `%lld notes · %@` |

## Detalle

### R5-07 · Una propiedad borra el frontmatter inválido 🧪
- **Dónde:** `Core/Markdown/Frontmatter.swift:121-129,141-146`, llamado desde `InspectorView.swift:304-317` y `BaseView.swift:409-415`.
- **Fix:**
  - Si `locate` encuentra el bloque pero `Yams.compose` falla, no reescribir: devolver nil o lanzar un error y mostrar `lastError`.
  - Escapar la clave con `scalar(p.key)` en `serialize`.

### R5-01 · Links rotos en imports con caracteres especiales 🧪
- **Dónde:** `Core/Import/Importers.swift:101,131,195,270,315`.
- **Fix:** pasar cada componente de carpeta por el reemplazo de `safeName` cuando `shortensLinks` está activo. Como alternativa, que `finish` mapee los destinos completos por coincidencia exacta.

### R5-02 · Escape incompleto en `HTMLToMarkdown` 🧪
- **Dónde:** `Core/Import/HTMLToMarkdown.swift:160-171`.
- **Fix:**
  - Escapar siempre `-` y `+` al inicio de línea.
  - Escapar `~` y `$`.
  - Codificar `%%` como `%&#37;`.

### R5-03 · Comentarios en `search.json` 🧪
- **Dónde:** `Core/Publish/SiteExporter.swift:87-91`.
- **Fix:** quitar `NoteParser.Regex.comment`, y también el código y la matemática, del texto indexado.

### R5-08 · Notas con nombre que empieza con `.` 📖
- **Dónde:**
  - `VaultModel.swift:136` (`newNote`) y `:150` (`rename`).
  - `Vault.entries()` con `.skipsHiddenFiles`.
  - Entradas desde `WebViewer.swift:82-90`, `WindowState+Plugins.swift:94-98`, `WindowState.swift:250-251` y `NoteIntents.swift:56`.
  - `Templates.dailyNotePath` con un formato vacío.
- **Fix:**
  - Un solo guard compartido (`Vault.availablePath`/`createNote` y `rename`) que quite los `.` iniciales y use "Untitled" si el nombre queda vacío.
  - Usar `yyyy-MM-dd` si el formato de la nota diaria está vacío.

### R5-09 · La configuración del vault no se recarga 📖
- **Dónde:** `VaultModel.swift:9,22,34-37,94-106`.
- **Fix:** en `externalChange`, recargar `app.json`, `bookmarks.json` y `themes()` cuando cambie su fecha de modificación, sin disparar los `didSet` de guardado.

### R5-04 · Operadores de tareas en la búsqueda 🧪
- **Dónde:** `Core/Search/Search.swift:77,115`.
- **Fix:** agregar el estado a `Term.task` y reutilizar `NoteParser.Regex.task`.

### R5-10 · Carrera en "Move to iCloud Drive" 📖
- **Dónde:** `AppModel.swift:188-192,246-261` y `SettingsView.swift:350`.
- **Fix:**
  - Bloquear la edición, o cerrar sin flush después del move, para no escribir en la ruta vieja.
  - Después del move, navegar a `.vault(newPath)` o cerrar la pantalla de Ajustes.

### R5-11 · `pendingLine` en vista de lectura 📖
- **Dónde:** `ReaderView.swift:16`, `NoteEditorView.swift:188`, `HTMLWebView.swift:171-176` e `InspectorView.swift:186`.
- **Fix:**
  - Consumir `pendingLine` en `ReaderView`, o tratarlo como un evento con contador.
  - Conservar `scrollY` al recargar.
  - Mapear las notas al pie.

### R5-05 · Resaltado perdido después de un link 🧪
- **Dónde:** `Core/Render/HTMLRenderer.swift:72`.
- **Fix:** buscar `==` y tags sobre un texto donde los destinos y títulos de los links estén en blanco.

### R5-06 · Tag dentro del texto de un link 🧪
- **Dónde:** `HTMLRenderer.swift:105` y `NoteParser.swift:124`.
- **Fix:** rechazar los tokens de tag dentro de un link Markdown (array `links`), y en el parser marcar como ocupado el rango completo del link.

### R5-12 · Plurales 📖
- **Fix:** agregar variaciones de plural en `en` y `es` a esas claves de `Localizable.xcstrings`.
