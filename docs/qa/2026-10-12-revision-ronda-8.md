# Revisión de Netherite — ronda 8 (2026-10-12)

Revisión de los arreglos de la ronda 7 ([2026-10-12-revision-ronda-7.md](2026-10-12-revision-ronda-7.md)).

**Estado base:** build macOS ✅, build iOS Simulator ✅, `swift test` 126/126 ✅.

**En vivo:** sin permiso de control de pantalla. R2-04, R2-05 y R2-06 siguen pendientes de verificar tecleando.

**Leyenda:** 🧪 confirmado con prueba · 📖 confirmado leyendo el código.

## Revisado sin hallazgos
- **`Vault.write` siguiendo symlinks:** es coherente con `read`, el vault raíz puede ser un symlink y un symlink roto se reemplaza por un archivo normal.
- **`move` con notas ilegibles:** se saltan bien.
- **`add(groups:)`:** el anidamiento está protegido.
- **Flujo N-01 con el modo lectura por defecto:** sigue funcionando.
- **Navegación:** seguir links que crean notas, la nota diaria, Back/Forward, workspaces y saltos a heading o bloque en lectura funcionan.
- **Strings nuevos:** JSON válido.

## Resumen

| ID | Sev. | Origen | Área | Problema |
|---|---|---|---|---|
| R8-01 | Alta | 🧪 | Datos | Las fechas se leen del symlink, no del archivo real: `refreshFromDisk` no ve ediciones externas y `move` las pisa con texto viejo (efecto de R7-01) |
| R8-05 | Media | 📖 | Navegación | Con "Open Notes in Reading View", los resultados de búsqueda y los backlinks abren la nota arriba, no en la coincidencia (regresión de R7-07) |
| R8-02 | Media | 🧪 | Import | Una línea `=` dentro de un blockquote o de una lista profunda se convierte en un heading setext (regresión de R7-03) |
| R8-06 | Baja-Media | 📖 | Vaults | El snapshot de R7-08 puede quedar huérfano (ID no persistido) y el mensaje asegura que se guardó aunque falle |
| R8-03 | Baja | 🧪 | Import | Los marcadores U+E000/U+E001 chocan con texto literal en `<pre>`, `<code>`, href, src y alt |
| R8-04 | Baja | 🧪 | Render | `$x$#tag` cuenta como tag para el índice pero no para el render (efecto de R7-04) |
| R8-07 | Baja | 📖 | Navegación | Las notas creadas que no se abren se quedan en `createdNotes` |
| R8-08 | Baja | 📖 | Composer | "Merge" deja el frontmatter de la nota origen en medio de la nota destino |

## Detalle

### R8-01 · Fechas de symlinks
- **Dónde:**
  - `Core/Index/VaultIndex.swift:67` (`record`) y `:83` (`refreshFromDisk`).
  - También `SharedVault.swift:92` y `Core/Bases/BaseFile.swift:224`.
- **Fix:** un helper `Vault.modificationDate(of:)` que lea `resourceValues` de `url(for:).resolvingSymlinksInPath()`, usado en todos esos lugares.

### R8-05 · Modo lectura y saltos a una línea
- **Dónde:** `WindowState.swift:222-224`, `SidebarPanels.swift:126`, `InspectorView.swift:96`, `ReaderView.swift:19-23` y `NoteEditorView.swift:188`.
- **Fix:** abrir en lectura solo si `line == nil` o si la línea es un ancla que el lector sabe resolver (heading, bloque o nota al pie). Si no, abrir en el editor.

### R8-02 · `=` dentro de un blockquote o una lista
- **Dónde:** `Core/Import/HTMLToMarkdown.swift:21`.
- **Fix:** escapar un `=` al inicio de un nodo dentro de `escape`, como antes de R7, o permitir los prefijos `>`/espacios/tabs en la regla.

### R8-06 · Snapshot del move a iCloud
- **Dónde:** `AppModel.swift:266` y `Core/Vault/VaultSettings.swift:90-124`.
- **Fix:** crear el `SnapshotStore` con el vault de origen antes de `setUbiquitous`, para que `id.json` viaje con la carpeta. Si `save` falla, que el mensaje no diga que se guardó.

### R8-03 · Marcadores del importador
- **Dónde:** `Core/Import/HTMLToMarkdown.swift:66,140,145,148`.
- **Fix:** usar no-caracteres (U+FDD0/U+FDD1) como marcadores, o sanear U+E000/U+E001 a U+FFFD también en esos caminos.

### R8-04 · `$x$#tag`
- **Dónde:** `Core/Render/HTMLRenderer.swift:114`.
- **Fix:** buscar tags sobre una copia donde la matemática esté en blanco con espacios, y usar U+FFFC solo para los resaltados.

### R8-07 · `createdNotes` acumula notas
- **Dónde:** `VaultModel.swift:185`, `WindowState+Plugins.swift:98` y `BaseView.swift:438-440`.
- **Fix:** marcar una nota como recién creada solo donde se abre justo después.

### R8-08 · Merge y frontmatter
- **Dónde:** `WindowState+Plugins.swift:110-111`.
- **Fix:** separar el frontmatter de la nota origen, anexar solo su cuerpo y fusionar sus propiedades en el frontmatter de la nota destino.
