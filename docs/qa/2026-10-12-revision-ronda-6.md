# Revisión de Netherite — ronda 6 (2026-10-12)

Revisión de los arreglos de la ronda 5 ([2026-10-12-revision-ronda-5.md](2026-10-12-revision-ronda-5.md)) y pasada final de riesgos de pérdida de datos: escrituras, coordinación con iCloud, mover y papelera, cierre, cambio de vault y extensiones.

**Estado base:** build macOS ✅, build iOS Simulator ✅, `swift test` 116/116 ✅.

**En vivo:** sin permiso de control de pantalla. R2-04, R2-05 y R2-06 siguen pendientes de verificar tecleando.

**Leyenda:** 🧪 confirmado con prueba · 📖 confirmado leyendo el código.

## Revisado sin hallazgos
- Los `try!` nuevos no pueden fallar.
- `Localizable.xcstrings` es JSON válido y los plurales tienen la forma correcta.
- No hay riesgos de pérdida de datos al cerrar ventanas o la app: se guarda en `willTerminate`, `scenePhase`, `onDisappear` y "Switch Vault…".
- `Vault.move`/`trash` funcionan bien, incluidos los renombres que solo cambian mayúsculas y el BOM UTF-8.

## Resumen

| ID | Sev. | Origen | Área | Problema |
|---|---|---|---|---|
| R6-01 | Media-Alta | 🧪 | Datos | `Yams.dump` corta a 80 columnas: una lista o clave larga deja el YAML inválido, la nota pierde sus propiedades y el Inspector queda bloqueado (en parte, regresión de R5-07) |
| R6-02 | Media-Alta | 🧪 | Import | En Evernote y HTML, una nota que empieza con `<hr>` se toma como frontmatter: se borra contenido o se pierden los metadatos |
| R6-07 | Media | 📖 | Datos | `reloadConfigIfChanged` aplica los valores por defecto si `app.json` o `bookmarks.json` no existen o no se pueden leer (iCloud desalojado), y el siguiente guardado pisa la configuración real (regresión de R5-09) |
| R6-08 | Media | 📖 | Datos | En la vista previa al pasar el cursor, marcar una tarea cambia la línea N de la nota completa, no la de la sección |
| R6-03 | Media | 🧪 | Datos | `VaultIndex.move` reescribe los links con el texto del índice y pisa ediciones externas que todavía no se refrescaron |
| R6-09 | Media-Baja | 📖 | Share | La Share Extension interpreta como frontmatter el contenido compartido que empieza con `---` |
| R6-04 | Baja-Media | 🧪 | Render | `==see [a](b)==` ya no se resalta y `[x](y)#t2` se renderiza como tag (regresión de R5-05) |
| R6-05 | Baja | 🧪 | Import | El escape de `%%` y `==` no cubre nodos de texto contiguos |
| R6-06 | Baja | 🧪 | Vault | Cada guardado reinicia la fecha de creación del archivo (`.atomic`) |
| R6-10 | Baja | 📖 | Vaults | Si falla la escritura de las ediciones hechas durante "Move to iCloud Drive", se pierden sin aviso; además, `externalChange` corre mientras `savesPaused` está activo |
| R6-11 | Baja | 📖 | Localización | Falta el plural en `"Snapshots are kept for %lld days…"` |
| R6-12 | Baja | 📖 | Lectura | El lector limpia `pendingLine` al hacer scroll, así que el editor ya no salta a la línea al volver a edición |

## Detalle

### R6-01 · Corte de línea de `Yams.dump`
- **Dónde:** `Core/Markdown/Frontmatter.swift:123-126,135-138`.
- **Fix:** `Yams.dump(object:, width: -1, allowUnicode: true)`.

### R6-02 · `<hr>` inicial en los importadores
- **Dónde:** `Core/Import/Importers.swift:95` y `Core/Import/HTMLToMarkdown.swift:57`.
- **Fix:**
  - Emitir `hr` como `***`.
  - En ENEX, anteponer el frontmatter serializado en vez de llamar a `replacing`.

### R6-07 · La configuración vuelve a los valores por defecto
- **Dónde:** `Netherite/App/VaultModel.swift:134-135`.
- **Fix:** recargar solo si el archivo existe y decodifica; si no, no aplicar nada y no actualizar `configDates`.

### R6-08 · Tareas en la vista previa
- **Dónde:** `Netherite/Features/Reader/ReaderView.swift:101-105` (`PagePreview`).
- **Fix:** `ctx.interactiveTasks = false` en `PagePreview`.

### R6-03 · `move` con el índice desactualizado
- **Dónde:** `Core/Index/VaultIndex.swift:180-193`.
- **Fix:** antes de reescribir una nota que no esté sucia, releerla del disco si su fecha de modificación cambió. Otra opción es refrescar el índice antes del move desde `VaultModel.move`.

### R6-09 · Contenido compartido que empieza con `---`
- **Dónde:** `ShareExtension/ShareViewController.swift:136`.
- **Fix:** `Frontmatter.replacing(in: "", with: props) + cuerpo`; no parsear nunca el cuerpo compartido.

### R6-04 · Regresión del blanqueo en el render
- **Dónde:** `Core/Render/HTMLRenderer.swift:104-110`.
- **Fix:** rellenar los rangos blanqueados con U+FFFC (no con espacios) y conservar los saltos de línea.

### R6-05 · `%%` y `==` repartidos entre nodos
- **Dónde:** `Core/Import/HTMLToMarkdown.swift:161-174`.
- **Fix:** codificar también los `%` y `=` al inicio y al final de cada nodo de texto.

### R6-06 · Fecha de creación
- **Dónde:** `Core/Vault/Vault.swift:92`.
- **Fix:** escribir en un archivo de `.itemReplacementDirectory` y usar `FileManager.replaceItemAt`.

### R6-10 · Escrituras durante "Move to iCloud Drive"
- **Dónde:** `Netherite/App/AppModel.swift:261`.
- **Fix:**
  - Avisar con `lastError` si la escritura falla y no limpiar `dirty`.
  - Saltarse `externalChange` mientras `savesPaused` esté activo.

### R6-11 · Plural de "Snapshots are kept for…"
- **Dónde:** `FileRecovery.swift:145`.
- **Fix:** agregar `variations.plural` en `en` y `es`.

### R6-12 · `pendingLine` y el editor
- **Dónde:** `Netherite/Features/Reader/ReaderView.swift:33` y `NoteEditorView.swift:187`.
- **Fix:** no limpiar `pendingLine` en el lector, para que el editor lo use al volver a edición; o actualizar el comportamiento documentado.
