# Revisión de Netherite — ronda 13 (2026-10-12)

Revisión del arreglo de la ronda 12 ([2026-10-12-revision-ronda-12.md](2026-10-12-revision-ronda-12.md)).

**Estado base:** build macOS ✅, build iOS Simulator ✅, `swift test` 139/139 ✅.

**En vivo:** sin permiso de control de pantalla. R2-04, R2-05 y R2-06 siguen pendientes de verificar tecleando.

## Revisado sin hallazgos
- **Anclas y alias:** anclas dentro de bloques reescritos que otros bloques usan, `*` dentro de strings o comentarios, alias en listas de flujo, merge keys `<<: *b`, bloques `|`, y borrar o renombrar la clave que tiene el ancla.
- **Claves especiales** y rendimiento: el camino normal no cambia.
- **`merging`:** sin problemas nuevos.

## Resumen

| ID | Sev. | Origen | Área | Problema |
|---|---|---|---|---|
| R13-01 | Baja-Media | 🧪 | Datos | El reintento con alias escapa los caracteres no ASCII (`José` → `"Jos\xE9"`) y corta las líneas a 80 columnas |

## Detalle

### R13-01 · `Yams.serialize(node:)` con opciones por defecto
- **Dónde:** `Core/Markdown/Frontmatter.swift:233`.
- **Fix:** `Yams.serialize(node:, width: -1, allowUnicode: true)`, igual que `scalar()`.
