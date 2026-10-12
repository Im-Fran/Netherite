# Revisión de Netherite — ronda 4 (2026-10-12)

Revisión de los arreglos de la ronda 3 ([2026-10-12-revision-ronda-3.md](2026-10-12-revision-ronda-3.md)) y de áreas que aún no se habían revisado: búsqueda, grafo, Bases, plantillas, importadores, Publish, paleta, Workspaces e Intents.

**Estado base:** build macOS ✅, build iOS Simulator ✅, `swift test` 94/94 ✅.

**Cómo se probó**
- **En vivo, macOS:** build aislada sobre un vault de prueba. Sin permiso de control de pantalla, solo se probó en segundo plano; Bases funciona bien.
- **Revisión estática:** core y app, sobre el diff `4a84e50..HEAD` y las áreas nuevas.

**Leyenda:** 🧪 confirmado con prueba · 📖 confirmado leyendo el código.

## Sigue pendiente de verificar en vivo (requiere teclear de verdad)
- **R2-04:** tarjetas del canvas sin caracteres perdidos.
- **R2-05:** tips mientras se escribe el título.
- **R2-06:** posición de la lista de `[[`.

## Resumen

| ID | Sev. | Origen | Área | Problema |
|---|---|---|---|---|
| R4-01 | Media-Alta | 📖 | Datos | Lo que se escribe en una nota abierta con otras mayúsculas (recientes, bookmarks, workspaces) se descarta sin aviso (regresión de R3-07) |
| R4-02 | Media | 📖 | Datos | Bookmarks y Workspaces no se actualizan al renombrar, mover o borrar: abren una nota fantasma |
| R4-03 | Media | 📖 | Vaults | "Move to iCloud Drive" no hace que la ventana siga al vault (vuelve al selector) y `SharedVault` queda con la ruta vieja |
| R4-04 | Media | 🧪 | Import | Notion/Evernote: los links y los embeds con nombres repetidos resuelven a la página o imagen de otra página; los renombres por colisión no se reflejan |
| R4-05 | Media-Baja | 🧪 | Import | `HTMLToMarkdown` no escapa el texto: `<b>`, `#`, `1.` y `[[x]]` literales pasan a ser Markdown |
| R4-06 | Media-Baja | 🧪 | Plantillas | Las fechas usan el calendario y los dígitos del locale (`th_TH` → 2569, `ar_SA` → dígitos árabes) |
| R4-07 | Baja-Media | 📖 | Búsqueda | La búsqueda no tiene debounce real: corre por cada tecla y puede mostrar resultados de una consulta vieja |
| R4-08 | Baja | 📖 | Grafo | El grafo se reconstruye y se recalienta con cada tecla |
| R4-09 | Baja | 📖 | Audio | La grabación rescatada queda inaccesible en iOS, y un fallo al moverla se ignora |
| R4-10 | Baja | 🧪 | Import | Un título que empieza con `.` genera una nota oculta |
| R4-11 | Baja | 🧪 | Import | `HTMLNode.parse` es cuadrático |
| R4-12 | Baja | 🧪 | Render | `[a ==b](c) d==` produce HTML mal anidado (regresión de R3-04) |
| R4-13 | Baja | 🧪 | Parser | `refDef` toma por definición líneas que no lo son, y se pierden tags |
| R4-14 | Baja | 🧪 | Rename | El rename borra el título de los links Markdown |
| R4-15 | Baja | 🧪 | Parser | Un título de `mdLink` puede cruzar líneas en blanco |
| R4-16 | Baja | 📖 | Búsqueda | La búsqueda con regex ignora "Distinguir mayúsculas" |
| R4-17 | Baja | 📖 | Bases/Búsqueda | `BaseFile.database(folder:)` no escapa `\`; un `]` sin abrir en la búsqueda deja `depth` en negativo |

## Detalle

### R4-01 · Se descarta lo escrito en una nota abierta con otras mayúsculas
- **Dónde:** `Netherite/App/VaultModel.swift:62,106`. `edit` sale sin hacer nada si `isGone`, que ahora usa `existsExactly`. Una entrada principal es `VaultWindow.swift:66`, que abre la última reciente comprobando con `exists`, que no distingue mayúsculas.
- **Reproducción:** con la app cerrada, renombrar `inbox.md` a `Inbox.md` en Finder (o recibir ese renombrado por iCloud). Al abrir, se abre `inbox.md` desde los recientes y lo escrito no se guarda.
- **Fix:**
  - Canonizar la ruta en un solo lugar, `WindowState.open`: resolver contra `index.files` sin distinguir mayúsculas y, si no existe, no abrir.
  - Que `edit` no descarte en silencio: avisar con `lastError` y cerrar el panel.

### R4-02 · Bookmarks y Workspaces con rutas viejas
- **Dónde:** `VaultModel.swift`, `move` (≈149-171) y `trash` (177-185); `SidebarPanels.swift:254-257`; `Workspaces.swift:24-35`.
- **Fix:**
  - Remapear `bookmarks` y `workspaces.json` en `move` con la misma regla que `recentFiles`, y quitarlos en `trash`.
  - Validar las rutas al abrir (lo cubre el fix de R4-01).

### R4-03 · "Move to iCloud Drive" no sigue al vault
- **Dónde:** `AppModel.swift:246,252` y `NetheriteApp.swift:103-107`.
- **Fix:**
  - Asignar `relocated[recent.path] = key(target)` antes de `close`, y quitarlo si el move falla.
  - Después del move, republicar `SharedVault` o reabrir el vault.

### R4-04 · Import de Notion y Evernote con nombres repetidos
- **Dónde:** `Core/Import/Importers.swift:99-102,188-190`.
- **Fix:** escribir primero todo, registrar la ruta final de cada nota y adjunto, y luego generar los links con `LinkResolver(files:).linkText(for:)`.

### R4-05 · `HTMLToMarkdown` no escapa el texto
- **Dónde:** `Core/Import/HTMLToMarkdown.swift:41,120`.
- **Fix:**
  - Escapar en los nodos de texto `\ * _ [ ] < > `` ` `` ==`, y `#`, `-`, `+` y `N.` al inicio de línea.
  - Volver a codificar `<` como `&lt;`.

### R4-06 · Fechas con el calendario del locale
- **Dónde:** `Core/Templates/Templates.swift:32-37`; también afecta a `SharedVault.swift:79`.
- **Fix:** calendario gregoriano y locale con `@numbers=latn`.

### R4-07 · Búsqueda sin debounce real
- **Dónde:** `Netherite/Features/Sidebar/SidebarPanels.swift:156-163`.
- **Fix:**
  - `do { try await Task.sleep(...) } catch { return }`.
  - `guard !Task.isCancelled` antes de asignar `hits`.
  - Que la clave de la tarea no dependa de `index.revision` por cada tecla.

### R4-08 · El grafo se reconstruye con cada tecla
- **Dónde:** `GraphView.swift:161-170,184`.
- **Fix:** usar una clave que solo cambie cuando cambian los links o los archivos.

### R4-09 · Grabación rescatada inaccesible
- **Dónde:** `AudioRecorder.swift:170-175`.
- **Fix:**
  - Guardarla en un lugar visible: en iOS, una carpeta de Documents que el selector de vaults ignore.
  - Usar un nombre único y avisar si mover el archivo falla.

### R4-10 · Nota oculta por un título con `.`
- **Dónde:** `Core/Import/Importers.swift:266-270` (`Writer.safeName`).
- **Fix:** quitar los puntos iniciales.

### R4-11 · `HTMLNode.parse` cuadrático
- **Dónde:** `Core/Import/HTMLToMarkdown.swift:187-188`.
- **Fix:** excluir `<` en los nombres y en los valores sin comillas.

### R4-12 · HTML mal anidado (regresión de R3-04)
- **Dónde:** `Core/Render/HTMLRenderer.swift:71-72,86-88`.
- **Fix:** guardar el rango completo de cada link y rechazar los tokens que lo cubran solo en parte.

### R4-13 · `refDef` demasiado laxo
- **Dónde:** `Core/Markdown/NoteParser.swift:124,208`.
- **Fix:** exigir la forma completa de CommonMark: destino, título opcional y fin de línea.

### R4-14 · El rename borra el título de los links
- **Dónde:** `Core/Index/VaultIndex.swift:240-242`.
- **Fix:** capturar el título en `mdLink` y volver a agregarlo.

### R4-15 · Títulos de `mdLink` que cruzan líneas en blanco
- **Dónde:** `Core/Markdown/NoteParser.swift:206`.
- **Fix:** no permitir líneas en blanco dentro del título.

### R4-16 · Regex sin distinguir mayúsculas
- **Dónde:** `Core/Search/Search.swift:68`.
- **Fix:** crear la regex según `caseSensitive`.

### R4-17 · Menores de Bases y búsqueda
- **`BaseFile.database(folder:)`:** escapar también `\`.
- **Tokenizador de búsqueda:** no dejar que `depth` baje de 0.
