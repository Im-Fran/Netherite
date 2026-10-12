# Revisión de Netherite — ronda 3 (2026-10-12)

Revisión de los arreglos de la ronda 2 ([2026-10-12-revision-ronda-2.md](2026-10-12-revision-ronda-2.md)).

**Estado base:** build macOS ✅, build iOS Simulator ✅, `swift test` 88/88 ✅.

**Cómo se probó**
- **En vivo, macOS:** build aislada (`cl.franciscosolis.netherite.review`) que abre directamente un vault de prueba copiado de `Fixtures/SampleVault`. No hubo permiso de control de pantalla, así que solo se usaron capturas, clics y menús en segundo plano, sin teclear de verdad.
- **Revisión estática:** una pasada al core y otra a la app, sobre el diff `af2afca..HEAD`.

**Leyenda:** 🔴 reproducido en vivo · 🧪 confirmado con prueba · 📖 confirmado leyendo el código.

## Verificado en vivo ✅
- **R2-22:** con la nueva CSP, la vista de lectura muestra bien CSS, imágenes, KaTeX (en línea y en bloque), Mermaid, resaltado de código, tablas, tareas y notas al pie.

## Pendiente de verificar en vivo (requiere teclear de verdad)
- **R2-04:** tarjetas del canvas sin caracteres perdidos.
- **R2-05:** tips mientras se escribe el título.
- **R2-06:** posición de la lista de `[[`. El agente lo verificó con un programa de prueba de AppKit, pero no en la app.

## Resumen

| ID | Sev. | Origen | Área | Problema |
|---|---|---|---|---|
| R3-01 | Media-Alta | 📖 | Datos | Un deep link con una ruta no canónica (otras mayúsculas, `/` inicial) duplica la nota en el índice, la cierra y descarta lo escrito |
| R3-02 | Media | 📖 | Sandbox | Mover a la papelera o a iCloud un vault abierto "en su ubicación" falla, porque `close()` suelta el acceso antes de la operación (regresión de R2-14) |
| R3-03 | Media | 🧪📖 | Recovery | `stableID(ledger:)` cree que el mismo vault es una copia si la ruta llega con o sin `/` final: regenera `id.json` y deja huérfano el historial |
| R3-04 | Media | 🧪 | Render | Un resaltado `==…==` o una fórmula `$…$` que contiene un link ya no se renderiza (regresión de R2-09) |
| R3-05 | Media-Baja | 🧪 | Render/Parser | Todavía entran tokens de tag en el `href` con títulos `'…'` o `(…)` y con definiciones de referencia; además el parser crea tags falsos |
| R3-06 | Baja-Media | 🧪 | Render | `sanitize` sigue siendo cuadrático cuando el único `>` queda dentro de una comilla sin cerrar |
| R3-07 | Baja-Media | 📖 | Datos | Si una nota con cambios sin guardar se renombra por fuera cambiando solo mayúsculas, lo escrito se pierde sin aviso |
| R3-08 | Baja | 🧪 | Rename | El escape del rename en el frontmatter falla con U+2028/U+0085/`\r` sueltos y con alias YAML |
| R3-09 | Baja | 🧪 | Parser | `blank` no preserva U+0085 (NEL) |
| R3-10 | Baja | 🧪 | Vaults | `folderName` todavía produce nombres que empiezan con `.` (`\u{200B}..`, `.\u{301}notes`) |
| R3-11 | Baja | 📖 | Audio | Si falla el guardado al cerrar la hoja, la grabación queda en `tmp` sin que se sepa dónde |
| R3-12 | Baja | 📖 | Spotlight | No se abren notas cuyo nombre contiene `\|` |
| R3-13 | Baja | 📖 | Datos | `trash` no guarda las ediciones pendientes antes de mover a la papelera |
| R3-14 | Baja | 📖 | Spotlight | Un resultado de Spotlight no hace nada si la ventana muestra el selector de vaults |

## Detalle

### R3-01 · Un deep link con una ruta no canónica pierde lo escrito
- **Dónde:** `Netherite/Features/Workspace/VaultWindow.swift:140-143` y `Netherite/App/VaultModel.swift:64,77,104`.
- **Causa:** `vault.exists` no distingue mayúsculas en APFS y además normaliza la ruta, pero `window.open` recibe la ruta sin canonizar. Al escribir, `edit()` crea un segundo registro para el mismo archivo. El refresco elimina una de las dos variantes, `removeMissing` cierra el panel y `save` sale sin escribir.
- **Reproducción:** con la nota `Inbox.md`, abrir `netherite://open?file=inbox` y escribir durante unos 2 s.
- **Fix:**
  - En `open`, resolver contra el índice: primero la coincidencia exacta después de `Vault.normalize`, y si no hay, una que no distinga mayúsculas.
  - En `edit`, llamar a `didCreate` solo si la ruta ya es canónica y ninguna entrada del índice coincide sin distinguir mayúsculas.

### R3-02 · La papelera y "mover a iCloud" fallan en vaults abiertos en su ubicación
- **Dónde:** `Netherite/App/AppModel.swift:188-205,240-242`.
- **Fix:** resolver el URL con su bookmark, iniciar el acceso dentro de `trashVault` y `moveToICloud`, operar sobre ese URL y detener el acceso al final.

### R3-03 · `stableID` con la ruta en dos formas
- **Dónde:** `Packages/NetheriteCore/Sources/NetheriteCore/Vault/VaultSettings.swift:94-107,120`. Las rutas se comparan como texto, con y sin `/` final.
- **Fix:** canonizar la ruta (resolver symlinks y quitar la `/` final) al escribir y al leer el ledger, y también en el hash. Agregar un test con las dos formas.

### R3-04 · Resaltados y fórmulas que contienen un link (regresión de R2-09)
- **Dónde:** `Core/Render/HTMLRenderer.swift:81-83`.
- **Reproducción:** `==see [docs](https://example.com) now==` ya no produce `<mark>`.
- **Fix:** usar un `IndexSet` aparte con los destinos de los links, y descartar solo los tokens que empiezan o terminan dentro de uno.

### R3-05 · Tags dentro del `href`, y tags falsos
- **Dónde:** `NoteParser.Regex.mdLink` (`NoteParser.swift:205`) y `HTMLRenderer.swift:420`.
- **Reproducción:** `[Jump](#Intro 'T')`, `[Jump](#Intro (T))` y `[Jump][r]\n\n[r]: #Intro`.
- **Fix:**
  - En `visitLink`/`visitImage`, restaurar los marcadores del destino con el texto original del token.
  - En el parser, aceptar títulos `'…'` y `(…)` y excluir las líneas de definición de referencias.

### R3-06 · `sanitize` sigue siendo cuadrático
- **Dónde:** `Core/Render/HTMLRenderer.swift:256,300`.
- **Reproducción:** `"<a " × n + "x=\">"`; con n = 8000 tarda 4,4 s en debug.
- **Fix:** si el escaneo llega al final del texto, emitir el resto escapado y terminar.

### R3-07 · Renombrado externo que solo cambia mayúsculas
- **Dónde:** `VaultModel.swift:93,104`.
- **Fix:** que `isGone` compruebe la existencia distinguiendo mayúsculas: listar la carpeta padre y comparar el nombre exacto.

### R3-08 · Escape del rename en casos borde
- **Dónde:** `Core/Index/VaultIndex.swift:212-214`.
- **Fix:** partir las líneas con el mismo conjunto de saltos que libyaml (`\n`, `\r`, U+0085, U+2028, U+2029) y elegir el escalar con `max(by:)` sobre su posición.

### R3-09 · `blank` y U+0085
- **Dónde:** `Core/Markdown/NoteParser.swift:177`.
- **Fix:** preservar también `0x85`.

### R3-10 · `folderName` y nombres que empiezan con `.`
- **Dónde:** `Core/Vault/VaultSettings.swift:128-131`.
- **Fix:** después de recortar, rechazar el nombre si su primer escalar es `.`, o repetir el recorte hasta que el nombre no cambie.

### R3-11 · La grabación queda en `tmp` si falla el guardado
- **Dónde:** `Netherite/Features/Plugins/AudioRecorder.swift:145,163-170`.
- **Fix:** mover el archivo a Application Support y decir dónde quedó en `lastError`.

### R3-12 · Spotlight y nombres con `|`
- **Dónde:** `Netherite/App/SystemIntegration.swift:46-49` y `VaultWindow.swift:73-79`.
- **Fix:** separar el vault de la ruta usando el prefijo `key(root) + "|"` de un vault conocido, o un separador que no pueda aparecer en una ruta.

### R3-13 · `trash` sin guardar antes
- **Dónde:** `VaultModel.swift:175-179`.
- **Fix:** guardar las rutas `dirty` afectadas antes de `index.trash`, igual que hace `move`.

### R3-14 · Spotlight en el selector de vaults
- **Dónde:** `Netherite/App/NetheriteApp.swift:78-92`.
- **Fix:** añadir `.onContinueUserActivity(CSSearchableItemActionType)` y convertir el resultado a un deep link `open?path=…&vault=…`.
