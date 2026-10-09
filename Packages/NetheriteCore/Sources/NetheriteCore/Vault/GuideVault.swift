import Foundation

/// A small vault that teaches Netherite by example (created from the start page).
public enum GuideVault {
    /// Writes the guide notes into `vault`; `spanish` picks the language.
    public static func write(to vault: Vault, spanish: Bool) throws {
        for (path, text) in spanish ? es : en {
            if !vault.exists(path) { try vault.write(text, to: path) }
        }
        let canvas = spanish ? canvasES : canvasEN
        if !vault.exists(canvas.path) { try vault.write(canvas.text, to: canvas.path) }
    }

    public static func startNote(spanish: Bool) -> String { spanish ? "Empieza aquí.md" : "Start Here.md" }

    // MARK: English

    static let en: [(String, String)] = [
        ("Start Here.md", """
        ---
        tags: [guide]
        ---
        # Welcome to Netherite

        This vault is a tour. Every note teaches one idea, and they're all **plain Markdown files** in a folder you own.

        > [!tip] How to use this guide
        > Click a link to follow it. Press ⌘E (or tap the book button) to switch between editing and reading. Nothing here can break — experiment freely.

        ## The tour
        1. [[Writing notes]] — formatting, callouts, math and diagrams
        2. [[Linking your thinking]] — links, backlinks and the graph
        3. [[Organizing]] — tags, properties, folders and bookmarks
        4. [[Daily notes and templates]]
        5. [[Visual thinking]] — Canvas and Bases
        6. [[Keyboard shortcuts]]

        When you're done, create your own vault from **File › Open Vault…**
        """),
        ("Writing notes.md", """
        ---
        tags: [guide]
        ---
        # Writing notes

        Netherite uses **Live Preview**: formatting appears as you type, and the Markdown shows again on the line you're editing.

        - **Bold** with `**text**` (⌘B), *italic* with `*text*` (⌘I)
        - ==Highlights== with `==text==`, ~~strikethrough~~ with `~~text~~`
        - Type `/` at the start of a line for headings, lists, tables, callouts and more.

        ## Tasks
        - [x] Open the guide
        - [ ] Click this checkbox
        - [ ] Press ⌘L on a line to turn it into a task

        ## Callouts
        > [!note] Callouts highlight information
        > Start a quote with `[!note]`, `[!tip]`, `[!warning]` or `[!danger]`.

        ## Math and diagrams
        $$
        e^{i\\pi} + 1 = 0
        $$

        ```mermaid
        graph LR
          Idea --> Note --> Link --> Insight
        ```

        Next: [[Linking your thinking]]
        """),
        ("Linking your thinking.md", """
        ---
        tags: [guide]
        ---
        # Linking your thinking

        Type `[[` and pick a note to link it — like [[Organizing]]. If the note doesn't exist yet, clicking the link creates it: try [[My first idea]].

        - Link to a heading with `[[Writing notes#Callouts]]`.
        - Show another note inside this one with `![[Keyboard shortcuts]]`.
        - Open the **right sidebar** to see **backlinks**: every note that links here.
        - Open the **graph view** (⌃⌘G, or from the command palette) to see how your notes connect.

        Next: [[Organizing]]
        """),
        ("Organizing.md", """
        ---
        tags: [guide, organizing]
        status: in progress
        rating: 4
        ---
        # Organizing

        Folders are optional. Most people rely on:

        - **Tags** like #guide or nested #projects/writing — click one to search for it.
        - **Properties**: the fields at the top of this note. Add them from the header or type `---` on the first line.
        - **Bookmarks** for the notes you open all the time (⋯ › Bookmark).
        - **Search** with operators: `tag:guide`, `path:Guide`, `"exact phrase"`, `[status:in progress]`.

        Next: [[Daily notes and templates]]
        """),
        ("Daily notes and templates.md", """
        ---
        tags: [guide]
        ---
        # Daily notes and templates

        Press ⇧⌘D, or choose it in the command palette, to open **today's note** — a note named after the date, perfect for journaling and quick capture. Its folder and format are in Settings.

        **Templates** are notes in the `Templates` folder. Insert one with ⇧⌘T, the command palette or `/`. Use `{{title}}`, `{{date}}` and `{{time}}` as placeholders — see [[Templates/Meeting]].

        Next: [[Visual thinking]]
        """),
        ("Visual thinking.md", """
        ---
        tags: [guide]
        ---
        # Visual thinking

        - **Canvas** is an infinite board for cards, notes, links and arrows. Open [[Guide board.canvas]] and double-click (or double-tap) empty space to add a card.
        - **Bases** turn notes into a table you can filter and sort by their properties. Open [[Guide notes.base]] — it lists every note tagged #guide.

        Next: [[Keyboard shortcuts]]
        """),
        ("Keyboard shortcuts.md", """
        ---
        tags: [guide]
        ---
        # Keyboard shortcuts

        | Action | Shortcut |
        | --- | --- |
        | Go to any note | ⌘O |
        | Command palette | ⌘P |
        | New note | ⌘N |
        | Reading view | ⌘E |
        | Search everywhere | ⇧⌘F |
        | Graph view | ⌃⌘G |
        | Today's note | ⇧⌘D |

        On iPhone and iPad, the same actions are in the toolbar and the ⋯ menu.

        Back to [[Start Here]]
        """),
        ("Templates/Meeting.md", """
        # {{title}}
        **Date:** {{date}} {{time}}

        ## Attendees
        -

        ## Notes
        -

        ## Actions
        - [ ]
        """),
        ("Guide notes.base", """
        filters:
          and:
            - file.hasTag("guide")
        views:
          - type: table
            name: Guide
            order:
              - file.name
              - status
              - rating
              - file.mtime
        """),
    ]

    static let canvasEN = (path: "Guide board.canvas", text: """
    {"nodes":[
     {"id":"c1","type":"text","text":"# Ideas board\\nDouble-click or double-tap empty space to add a card, drag the dots on a card's edge to connect it.","x":-40,"y":-20,"width":320,"height":160,"color":"6"},
     {"id":"c2","type":"file","file":"Start Here.md","x":360,"y":-60,"width":340,"height":260},
     {"id":"c3","type":"text","text":"Cards can hold **Markdown**, notes, web pages or groups.","x":-40,"y":220,"width":320,"height":110,"color":"4"}
    ],"edges":[{"id":"e1","fromNode":"c1","fromSide":"right","toNode":"c2","toSide":"left","label":"see"}]}
    """)

    // MARK: Español

    static let es: [(String, String)] = [
        ("Empieza aquí.md", """
        ---
        tags: [guía]
        ---
        # Bienvenido a Netherite

        Esta bóveda es un recorrido. Cada nota enseña una idea, y todas son **archivos Markdown** en una carpeta que es tuya.

        > [!tip] Cómo usar esta guía
        > Haz clic en un enlace para seguirlo. Pulsa ⌘E (o toca el botón del libro) para cambiar entre edición y lectura. Aquí nada se rompe: experimenta.

        ## El recorrido
        1. [[Escribir notas]]: formato, callouts, fórmulas y diagramas
        2. [[Conectar ideas]]: enlaces, enlaces entrantes y el grafo
        3. [[Organizar]]: etiquetas, propiedades, carpetas y marcadores
        4. [[Notas diarias y plantillas]]
        5. [[Pensamiento visual]]: lienzos y bases
        6. [[Atajos de teclado]]

        Cuando termines, crea tu propia bóveda desde **Archivo › Abrir bóveda…**
        """),
        ("Escribir notas.md", """
        ---
        tags: [guía]
        ---
        # Escribir notas

        Netherite usa **Live Preview**: el formato aparece mientras escribes, y el Markdown vuelve a verse en la línea que editas.

        - **Negrita** con `**texto**` (⌘B), *cursiva* con `*texto*` (⌘I)
        - ==Resaltado== con `==texto==`, ~~tachado~~ con `~~texto~~`
        - Escribe `/` al inicio de una línea para títulos, listas, tablas, callouts y más.

        ## Tareas
        - [x] Abrir la guía
        - [ ] Marca esta casilla
        - [ ] Pulsa ⌘L en una línea para convertirla en tarea

        ## Callouts
        > [!note] Los callouts destacan información
        > Empieza una cita con `[!note]`, `[!tip]`, `[!warning]` o `[!danger]`.

        ## Fórmulas y diagramas
        $$
        e^{i\\pi} + 1 = 0
        $$

        ```mermaid
        graph LR
          Idea --> Nota --> Enlace --> Descubrimiento
        ```

        Siguiente: [[Conectar ideas]]
        """),
        ("Conectar ideas.md", """
        ---
        tags: [guía]
        ---
        # Conectar ideas

        Escribe `[[` y elige una nota para enlazarla, como [[Organizar]]. Si la nota no existe, al hacer clic en el enlace se crea: prueba con [[Mi primera idea]].

        - Enlaza a un título con `[[Escribir notas#Callouts]]`.
        - Muestra otra nota dentro de esta con `![[Atajos de teclado]]`.
        - Abre la **barra lateral derecha** para ver los **enlaces entrantes**: las notas que enlazan aquí.
        - Abre la **vista de grafo** (⌃⌘G, o desde la paleta de comandos) para ver cómo se conectan tus notas.

        Siguiente: [[Organizar]]
        """),
        ("Organizar.md", """
        ---
        tags: [guía, organizar]
        status: en curso
        rating: 4
        ---
        # Organizar

        Las carpetas son opcionales. Lo más útil suele ser:

        - **Etiquetas** como #guía o anidadas como #proyectos/escritura: haz clic en una para buscarla.
        - **Propiedades**: los campos al inicio de esta nota. Añádelas desde la cabecera o escribe `---` en la primera línea.
        - **Marcadores** para las notas que abres a diario (⋯ › Marcador).
        - **Búsqueda** con operadores: `tag:guía`, `path:Guía`, `"frase exacta"`, `[status:en curso]`.

        Siguiente: [[Notas diarias y plantillas]]
        """),
        ("Notas diarias y plantillas.md", """
        ---
        tags: [guía]
        ---
        # Notas diarias y plantillas

        Pulsa ⇧⌘D, o elígela en la paleta de comandos, para abrir la **nota de hoy**: una nota con la fecha como nombre, ideal para un diario o apuntes rápidos. Su carpeta y formato están en Ajustes.

        Las **plantillas** son notas de la carpeta `Templates`. Inserta una con ⇧⌘T, la paleta de comandos o `/`. Usa `{{title}}`, `{{date}}` y `{{time}}` como marcadores; mira [[Templates/Reunión]].

        Siguiente: [[Pensamiento visual]]
        """),
        ("Pensamiento visual.md", """
        ---
        tags: [guía]
        ---
        # Pensamiento visual

        - Un **lienzo** es un tablero infinito de tarjetas, notas, enlaces y flechas. Abre [[Tablero guía.canvas]] y haz doble clic (o toca dos veces) en un espacio vacío para añadir una tarjeta.
        - Las **bases** convierten notas en una tabla que puedes filtrar y ordenar por sus propiedades. Abre [[Notas de la guía.base]]: lista todas las notas con la etiqueta #guía.

        Siguiente: [[Atajos de teclado]]
        """),
        ("Atajos de teclado.md", """
        ---
        tags: [guía]
        ---
        # Atajos de teclado

        | Acción | Atajo |
        | --- | --- |
        | Ir a cualquier nota | ⌘O |
        | Paleta de comandos | ⌘P |
        | Nueva nota | ⌘N |
        | Vista de lectura | ⌘E |
        | Buscar en todo | ⇧⌘F |
        | Vista de grafo | ⌃⌘G |
        | Nota de hoy | ⇧⌘D |

        En iPhone y iPad, las mismas acciones están en la barra de herramientas y el menú ⋯.

        Volver a [[Empieza aquí]]
        """),
        ("Templates/Reunión.md", """
        # {{title}}
        **Fecha:** {{date}} {{time}}

        ## Asistentes
        -

        ## Notas
        -

        ## Acciones
        - [ ]
        """),
        ("Notas de la guía.base", """
        filters:
          and:
            - file.hasTag("guía")
        views:
          - type: table
            name: Guía
            order:
              - file.name
              - status
              - rating
              - file.mtime
        """),
    ]

    static let canvasES = (path: "Tablero guía.canvas", text: """
    {"nodes":[
     {"id":"c1","type":"text","text":"# Tablero de ideas\\nHaz doble clic o toca dos veces un espacio vacío para añadir una tarjeta y arrastra los puntos del borde para conectarla.","x":-40,"y":-20,"width":320,"height":160,"color":"6"},
     {"id":"c2","type":"file","file":"Empieza aquí.md","x":360,"y":-60,"width":340,"height":260},
     {"id":"c3","type":"text","text":"Las tarjetas pueden contener **Markdown**, notas, páginas web o grupos.","x":-40,"y":220,"width":320,"height":110,"color":"4"}
    ],"edges":[{"id":"e1","fromNode":"c1","fromSide":"right","toNode":"c2","toSide":"left","label":"ver"}]}
    """)
}
