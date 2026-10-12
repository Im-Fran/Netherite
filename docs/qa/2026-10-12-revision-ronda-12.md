# Revisión de Netherite — ronda 12 (2026-10-12)

Revisión de los arreglos de la ronda 11 ([2026-10-12-revision-ronda-11.md](2026-10-12-revision-ronda-11.md)).

**Estado base:** build macOS ✅, build iOS Simulator ✅, `swift test` 137/137 ✅.

**En vivo:** sin permiso de control de pantalla. R2-04, R2-05 y R2-06 siguen pendientes de verificar tecleando.

## Revisado sin hallazgos
- **Rendimiento:** el compose extra en cada `replacing` cuesta unos 0,85 ms con un frontmatter extremo (200 claves) y es despreciable con uno normal.
- **Frontmatter vacío o solo con comentarios:** se maneja bien.
- **`[[Sub/X.canvas]]`:** crea `Sub/X.canvas` dentro del vault, y el segundo clic lo resuelve sin duplicar.
- **`merging`:** los bloques copiados no capturan alias ajenos.
- **Adjuntos:** `PagePreview` y `follow` usan la misma condición, y el string tiene su traducción `es`.

## Resumen

| ID | Sev. | Origen | Área | Problema |
|---|---|---|---|---|
| R12-01 | Baja | 🧪 | Datos | El respaldo de `replacing` cuando el YAML no compone convierte los mapas anidados en texto y borra los comentarios de todo el frontmatter |

## Detalle

### R12-01 · Respaldo de `replacing` con pérdida de estructura
- **Dónde:** `Core/Markdown/Frontmatter.swift:164` y `value(of:)` (línea 80).
- **Reproducción:** con `# keep me`, `meta: {a: 1, b: [x]}` (en bloque), `base: &d 2024-01-01` y `updated: *d`, editar `base` deja `meta` como string y quita el comentario.
- **Fix:**
  1. Antes del respaldo completo, reintentar `merge` reserializando solo los bloques que contienen un alias (`*nombre`) y conservando los demás tal cual.
  2. Si eso tampoco compone, rehacer a nivel de nodo YAML: componer el original, cambiar las claves editadas y emitirlo con `Yams.serialize(node:)`, para que los mapas sigan siendo mapas.
