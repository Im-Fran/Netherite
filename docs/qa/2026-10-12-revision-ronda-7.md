# Revisión de Netherite — ronda 7 (2026-10-12)

Revisión de los arreglos de la ronda 6 ([2026-10-12-revision-ronda-6.md](2026-10-12-revision-ronda-6.md)) y una pasada amplia por las áreas que no aparecían en ningún registro anterior.

**Estado base:** build macOS ✅, build iOS Simulator ✅, `swift test` 122/122 ✅.

**En vivo:** sin permiso de control de pantalla. R2-04, R2-05 y R2-06 siguen pendientes de verificar tecleando.

**Leyenda:** 🧪 confirmado con prueba · 📖 confirmado leyendo el código.

## Revisado sin hallazgos
- **Fixes de la ronda 6 en la app:** `readerLine`/`pendingLine`, `reloaded<T>`, `savesPaused`, `move(skipping: dirty)`, la vista previa, la Share Extension y los plurales. Todos están bien.
- **`replaceItemAt`:**
  - Conserva permisos, xattrs, `FinderInfo`, tags de Finder y la fecha de creación.
  - Funciona en FAT32, exFAT y HFS+ en solo lectura.
  - Va dentro de la coordinación `.forReplacing`.
- **U+FFFC:** sin efecto en math, código, wikilinks, footnotes ni block IDs.
- **Pasada amplia sin problemas:** `BaseBoard`, `Palette`, `EditorController`, `Exporting`, `SyncSettings`, la galería de plantillas, `MeetingNotes` y `VaultModel+Extras`.

## Resumen

| ID | Sev. | Origen | Área | Problema |
|---|---|---|---|---|
| R7-01 | Media | 🧪 | Datos | Una nota que es un symlink a un archivo no se puede guardar (`replaceItemAt` falla) y queda sucia para siempre (regresión de R6-06) |
| R7-02 | Media-Baja | 🧪 | Datos | `move` vuelve a crear notas borradas por fuera, o deja una copia vieja junto al placeholder de iCloud (R6-03 incompleto) |
| R7-05 | Media-Baja | 📖 | Slides | En una presentación, marcar una tarea cambia otra línea de la nota (líneas relativas a la diapositiva) |
| R7-06 | Media-Baja | 📖 | Datos | "Merge" del Note composer pisa ediciones externas con el texto viejo del índice |
| R7-04 | Baja-Media | 🧪 | Render | Un resaltado que contiene un wikilink o una fórmula no se renderiza (`==see [[w]]==`) |
| R7-07 | Baja-Media | 📖 | Ajustes | "Open Notes in Reading View" no hace nada |
| R7-03 | Baja | 🧪 | Import | Cada `%` (o `=`) al borde de un texto importado queda como `&#37;` (o `\=`) en el `.md`, y la búsqueda no lo encuentra (efecto de R6-05) |
| R7-08 | Baja | 📖 | Vaults | El límite de R6-10: si falla la escritura en la nueva ubicación al mover a iCloud Drive, el texto se pierde (solo se avisa) |

## Detalle

### R7-01 · Symlinks a archivos
- **Dónde:** `Core/Vault/Vault.swift:87,95,100`.
- **Fix:** escribir en `url(for: path).resolvingSymlinksInPath()`, igual que hace `read`.

### R7-02 · `move` y notas borradas por fuera
- **Dónde:** `Core/Index/VaultIndex.swift:185`.
- **Fix:** si `record` devuelve nil, o la nota no existe en disco y no está en `skipping`, saltarla y quitarla del índice.

### R7-05 · Tareas en Slides
- **Dónde:** `Netherite/Features/Plugins/Slides.swift:28`.
- **Fix:** `ctx.interactiveTasks = false`, como en R6-08.

### R7-06 · Merge con texto viejo
- **Dónde:** `Netherite/App/WindowState+Plugins.swift:108,111-115`.
- **Fix:** releer del disco las notas que no estén en `dirty` (las que enlazan a la fuente y el destino) antes de reescribirlas, como hace `VaultIndex.move`.

### R7-04 · Resaltados con wikilinks o fórmulas
- **Dónde:** `Core/Render/HTMLRenderer.swift:71,108-110`.
- **Fix:** reemplazar solo los delimitadores `==` con tokens `<mark>`/`</mark>`, y comprobar `taken` solo en esos rangos.

### R7-07 · "Open Notes in Reading View"
- **Dónde:** `VaultSettingsView.swift:176` y `WindowState.swift:80,221`.
- **Fix:** que `Pane.open` acepte `reading:`, y que `WindowState.open` pase `settings.defaultToReadingMode`, salvo para notas nuevas.

### R7-03 · `%` al borde de un nodo
- **Dónde:** `Core/Import/HTMLToMarkdown.swift:171`.
- **Fix:** escapar `%%` y `==` sobre el texto inline ya unido, no nodo por nodo.

### R7-08 · Texto perdido al mover a iCloud Drive
- **Dónde:** `Netherite/App/AppModel.swift:262-265`.
- **Fix:** si la escritura falla, guardar el texto en File Recovery (`SnapshotStore(vault:).save(text, for:)`) y que el mensaje diga dónde recuperarlo.
