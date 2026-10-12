# Revisión de Netherite — ronda 11 (2026-10-12)

Revisión de los arreglos de la ronda 10 ([2026-10-12-revision-ronda-10.md](2026-10-12-revision-ronda-10.md)) y última pasada de seguridad sobre todo el código.

**Estado base:** build macOS ✅, build iOS Simulator ✅, `swift test` 135/135 ✅.

**En vivo:** sin permiso de control de pantalla. R2-04, R2-05 y R2-06 siguen pendientes de verificar tecleando.

**Leyenda:** 🧪 confirmado con prueba · 📖 confirmado leyendo el código.

## Pasada de seguridad: nada reabierto
- **Esquema `nth`:** confinado y sin CORS `*`.
- **Visor web:** sin handler `nth`.
- **Render:** CSP con nonce, y con hash en las páginas publicadas.
- **Import:** límites de ZIP.
- **Deep links:** solo a vaults conocidos y con `canonicalPath`.
- **Share Extension:** saneada.
- **`follow` con `../`:** queda confinado por `Vault.normalize`.

## Resumen

| ID | Sev. | Origen | Área | Problema |
|---|---|---|---|---|
| R11-01 | Media | 🧪 | Datos | Editar o fusionar la clave que lleva un ancla YAML (`&d`) deja huérfano el alias (`*d`): YAML inválido, la nota pierde sus propiedades y el Inspector se bloquea |
| R11-02 | Baja | 🧪 | Composer | Un alias copiado en un merge se resuelve contra un ancla homónima del destino y toma otro valor |
| R11-03 | Baja | 📖 | Links | Seguir `[[X.canvas]]`, `[[X.base]]` o un adjunto inexistente no hace nada ni muestra ningún aviso |

## Detalle

### R11-01 · Anclas YAML al editar
- **Dónde:** `Core/Markdown/Frontmatter.swift:161-165` (`replacing`) y `:218-229` (`merge`).
- **Fix:** comprobar siempre, haya o no `verbatim`, si el YAML resultante compone como mapping. Si no compone, serializar todas las propiedades (`props.map { serialize([$0]) }`), sin llamar recursivamente a `replacing`.

### R11-02 · Alias resuelto contra otra ancla
- **Dónde:** `Frontmatter.swift:164` y `merging` (`:177-183`).
- **Fix:** no copiar tal cual un bloque con un alias cuya ancla no esté en ese mismo bloque.

### R11-03 · Links a canvas, base o adjuntos inexistentes
- **Dónde:** `Netherite/App/WindowState.swift:264` y `LinkResolver.newNoteName`.
- **Fix:**
  - Para `.canvas` y `.base`, crear el archivo vacío en la ruta del link (con el contenido de `newCanvas`/`newBase`) y abrirlo.
  - Para adjuntos, no crear nada y mostrar en `lastError` que el archivo no existe.
