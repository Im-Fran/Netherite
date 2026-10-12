# Revisión de Netherite — ronda 15 (2026-10-12)

Revisión del arreglo de la ronda 14 ([2026-10-12-revision-ronda-14.md](2026-10-12-revision-ronda-14.md)).

**Estado base:** build macOS ✅, build iOS Simulator ✅, `swift test` 143/143 ✅.

## Revisado sin hallazgos
- **Guarda de round-trip:** la igualdad de `Node` en Yams compara el `string` y el `resolvedTag`, no el estilo ni las marcas. Por eso acepta los emoji literales y nunca un valor alterado. Se probó con 13 escalares problemáticos.
- **`BaseFile.yaml` sin límite de ancho:** es idempotente con filtros anidados, expresiones de más de 800 caracteres y fórmulas multilínea.
- **Coste:** solo se paga cuando hay `\U` en el texto, unos 4 ms con 50 propiedades con emoji en debug.

## Resumen

| ID | Sev. | Origen | Área | Problema |
|---|---|---|---|---|
| R15-01 | Baja (cosmético) | 🧪 | YAML | Un único `"` desbalanceado en un escalar sin comillas o entre comillas simples desalinea los tramos: la guarda rechaza todo el documento y todos los emoji del archivo quedan escapados (los valores se conservan) |

## Detalle

### R15-01 · Guarda sobre el documento completo
- **Dónde:** `Core/Markdown/Frontmatter.swift` (`unescapingAstral`).
- **Fix:** si la guarda del documento completo falla, intentar línea por línea y aceptar cada línea solo si el documento sigue leyéndose igual.
