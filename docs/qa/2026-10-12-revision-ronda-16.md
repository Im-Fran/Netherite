# Revisión de Netherite — ronda 16 (2026-10-12)

Revisión final del arreglo de la ronda 15 ([2026-10-12-revision-ronda-15.md](2026-10-12-revision-ronda-15.md)) y una pasada general sobre todo el diff de las 15 rondas (`0163314..HEAD`).

**Estado base:** build macOS ✅, build iOS Simulator ✅, `swift test` 144/144 ✅.

## Revisado sin hallazgos
- **Guarda de `unescapingAstral`:** no puede aceptar un cambio de valor, porque cada candidato se compara con el compose del original.
- **Escalares multilínea:** quedan en una sola línea porque se escriben con `width: -1`.
- **Pasada general:** `Vault.write`, `normalize`/`noteName`, `SharedVault`, la Share Extension, `VaultModel` y `NoteEditorView` no tienen bugs nuevos de pérdida de datos ni crashes.

## Resumen

| ID | Sev. | Origen | Área | Problema |
|---|---|---|---|---|
| R16-01 | Media (rendimiento) | 🧪 | YAML | El reintento línea por línea de R15-01 hace un compose del documento completo por cada línea con `\U`. Con una propiedad mapping que tiene una comilla suelta y 400 claves con emoji tarda 0,3 s por parse, que se ejecuta en el main actor en cada tecla |

## Detalle

### R16-01 · Reintento cuadrático
- **Dónde:** `Core/Markdown/Frontmatter.swift:143-157`.
- **Fix:** limitar el reintento a unas pocas líneas (por ejemplo 32). Por encima de eso, conservar la salida escapada, que es un efecto solo cosmético.
