# Revisión de Netherite — ronda 9 (2026-10-12)

Revisión de los arreglos de la ronda 8 ([2026-10-12-revision-ronda-8.md](2026-10-12-revision-ronda-8.md)).

**Estado base:** build macOS ✅, build iOS Simulator ✅, `swift test` 130/130 ✅.

**En vivo:** sin permiso de control de pantalla. R2-04, R2-05 y R2-06 siguen pendientes de verificar tecleando.

**Leyenda:** 🧪 confirmado con prueba · 📖 confirmado leyendo el código.

## Revisado sin hallazgos
- **`HTMLToMarkdown`:** `=` en citas y listas anidadas, `==`, `---`, código y enlaces intactos, y entidades neutralizadas.
- **Render:** `$x$#t` sale como tag y `==$x$==` como resaltado.
- **File Recovery al mover a iCloud:** el `SnapshotStore` creado antes del move conserva el ID, y `save` devuelve `Bool`.
- **Notas nuevas:** todos los llamadores de `newNote(opens:)` pasan el valor correcto.
- **Symlinks:** `VaultIndex`, `BaseRow` y `SharedVault` toman la fecha del archivo real.
- **Tags después de un link:** `NoteParser` y el renderer coinciden en 32 variantes de `[x](y)#t`, así que no hay inconsistencia.

## Resumen

| ID | Sev. | Origen | Área | Problema |
|---|---|---|---|---|
| R9-01 | Media | 🧪 | Composer | Merge pierde tags o aliases del origen si uno de los dos lados es un escalar (`tags: foo`), y el origen se manda a la papelera |
| R9-02 | Baja-Media | 🧪 | Composer | Merge reserializa las claves nuevas del origen: un mapping anidado se vuelve string, y fechas y hex quedan entre comillas |
| R9-03 | Baja | 📖 | Canvas | `CanvasModel` sigue leyendo la fecha del symlink: no ve ediciones externas y las sobrescribe al guardar |
| R9-04 | Baja | 📖 | Navegación | Un resultado de búsqueda sin ancla en la nota que ya está abierta en lectura no hace nada |

## Detalle

### R9-01 · Merge con un lado escalar
- **Dónde:** `Netherite/App/WindowState+Plugins.swift:122`.
- **Fix:** si alguno de los dos lados es `.list`, o la clave es `tags`/`tag`/`aliases`/`alias`, unir los valores con `.strings` sin duplicados.

### R9-02 · Merge y tipos YAML
- **Dónde:** `WindowState+Plugins.swift:121`.
- **Fix:** copiar tal cual el bloque YAML original de cada clave nueva del origen, y reserializar solo las listas que se unen.

### R9-03 · Canvas detrás de un symlink
- **Dónde:** `Netherite/Features/Canvas/CanvasModel.swift:59`.
- **Fix:** `vault.modificationDate(of: path)`.

### R9-04 · Resultado de búsqueda en la nota abierta en lectura
- **Dónde:** `WindowState.swift:224-232` y `Pane.open` (`:76`).
- **Fix:** si hay una línea sin ancla y la nota ya está abierta, poner `pane.reading = false` de todos modos.
