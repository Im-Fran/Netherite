# Revisión de Netherite — ronda 10 (2026-10-12)

Revisión de los arreglos de la ronda 9 ([2026-10-12-revision-ronda-9.md](2026-10-12-revision-ronda-9.md)) y recorrido de punta a punta de las tres rutas de usuario más comunes:
- crear, editar y renombrar una nota;
- abrir y cambiar de vault;
- buscar y seguir links.

**Estado base:** build macOS ✅, build iOS Simulator ✅, `swift test` 132/132 ✅.

**En vivo:** sin permiso de control de pantalla. R2-04, R2-05 y R2-06 siguen pendientes de verificar tecleando.

**Leyenda:** 🧪 confirmado con prueba · 📖 confirmado leyendo el código.

## Revisado sin hallazgos
- **`Frontmatter.replacing` con `verbatim`:** el resultado no cambia para ningún llamador existente (Inspector, Bases, Share Extension, TemplateGallery, FormatConverter, importadores).
- **`Frontmatter.blocks()`:** parte bien comentarios, listas multilínea y bloques literales `|` y `>`.
- **Otros arreglos de la ronda 9:** `CanvasModel.modificationDate` y el `anchored` de `WindowState.open` funcionan bien.
- **Abrir y cambiar de vault, y la búsqueda:** sin bugs.

## Resumen

| ID | Sev. | Origen | Área | Problema |
|---|---|---|---|---|
| R10-01 | Media | 🧪 | Composer | Merge borra el valor escalar del destino (número, fecha o booleano) cuando el origen trae una lista |
| R10-03 | Media | 🧪 | Links | Seguir un link sin resolver que incluye extensión crea `Plan.md.md`; con `[[Diagram.canvas]]` crea `Diagram.canvas.md` |
| R10-02 | Baja | 🧪 | Composer | La copia verbatim de un alias YAML (`*d`) sin su ancla deja inválido el frontmatter del destino |

## Detalle

### R10-01 · Merge con escalares no textuales
- **Dónde:** `Core/Markdown/Frontmatter.swift:185-189`. `PropertyValue.strings` devuelve `[]` para `.number`, `.date` y `.bool`.
- **Reproducción:** `merging("---\nx: [a]\n---\nS", into: "---\nx: 5\n---\nT")` da `x: [a]` y se pierde el `5`.
- **Fix:** en `merging`, tomar como lista de partida `[displayString]` para cualquier escalar que no sea nulo ni lista.

### R10-03 · Links con extensión
- **Dónde:** `Netherite/App/WindowState.swift:264-266` (`follow`).
- **Reproducción:** con `[x](Plan.md)` sin destino, cmd-click o click en el lector crea `Plan.md.md`.
- **Fix:** quitar la extensión `.md` antes de `newNote`; para otras extensiones conocidas (`.canvas`, `.base`, adjuntos), no crear una nota.

### R10-02 · Alias YAML en la copia verbatim
- **Dónde:** `Core/Markdown/Frontmatter.swift:178-179`.
- **Reproducción:** con `base: &d 2024-01-01` y `updated: *d` en el origen, y `base` ya presente en el destino, el destino queda con `updated: *d` sin ancla y `parse` devuelve `[]`.
- **Fix:** no usar verbatim si el YAML resultante no compone como mapping (validar con `Yams.compose`), y en ese caso volver a `serialize`.
