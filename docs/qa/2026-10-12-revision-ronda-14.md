# Revisión de Netherite — ronda 14 (2026-10-12)

Revisión del arreglo de la ronda 13 ([2026-10-12-revision-ronda-13.md](2026-10-12-revision-ronda-13.md)) y de otras rutas que escriben YAML o JSON.

**Estado base:** build macOS ✅, build iOS Simulator ✅, `swift test` 141/141 ✅.

**En vivo:** sin permiso de control de pantalla. R2-04, R2-05 y R2-06 siguen pendientes de verificar tecleando.

## Revisado sin hallazgos
- **Round-trip correcto:** `\\` consecutivos, banderas con caracteres de etiqueta, U+10FFFF, cadenas multilínea y surrogates.
- **Canvas JSON:** escribe Unicode literal.
- **Plantillas, importadores, Share Extension y FormatConverter:** pasan por `Frontmatter.replacing`.

## Resumen

| ID | Sev. | Origen | Área | Problema |
|---|---|---|---|---|
| R14-01 | Media | 🧪 | Datos | `unescapingAstral` toma por "tramo entre comillas dobles" cualquier par de `"`, incluso dentro de escalares sin comillas o de claves, y convierte un `\UXXXXXXXX` literal en un carácter: el valor cambia, y puede cambiar incluso en una propiedad que no se editó (reintento de alias) |
| R14-02 | Baja-Media | 🧪 | Bases | Los `.base` se reescriben con acentos y emoji escapados y con las líneas cortadas a 80 columnas (`BaseFile.swift:168`) |

## Detalle

### R14-01 · Desescape fuera de las comillas dobles
- **Dónde:** `Core/Markdown/Frontmatter.swift:143-162`, usado en las líneas 80, 136 y 258.
- **Reproducción:** el texto `a "b \U0001F600 c" d` se guarda como `a "b 😀 c" d`.
- **Fix:** aceptar el desescape solo si el YAML resultante compone al mismo nodo que el original; si no, conservar la salida escapada.

### R14-02 · `.base` con escapes
- **Dónde:** `Core/Bases/BaseFile.swift:168`.
- **Fix:** `Yams.serialize(node:, width: -1, allowUnicode: true)` más `unescapingAstral`, con la salvaguarda de R14-01.
