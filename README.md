# qt-docs.nvim

Die Qt-Dokumentation direkt in Neovim lesen – offline aus den `.qch`-Dateien bzw. der
HTML-Doku deiner Qt-Installation, mit Online-Fallback auf doc.qt.io.

- `:QtDoc` auf `str.arg(…)` öffnet **QString::arg** – das Symbol wird über clangd aufgelöst
  (Methode → Klasse, Variable → ihr Typ, Enum-Wert → `Qt::AlignLeft`)
- Hover-Float mit nur dem passenden Abschnitt (wie `K`), optional als `K`-Ersatz:
  Qt-Doku, wenn das Symbol in der Doku steht, sonst normaler LSP-Hover
- Seiten als Markdown (Überschriften, Codeblöcke mit C++-Highlighting, Tabellen, Links),
  funktioniert mit render-markdown.nvim / markview.nvim
- Links folgen (auch in andere Module und doc.qt.io-Links lokal), Verlauf zurück/vor,
  Inhaltsverzeichnis, Suche über alle Stichwörter (Klassen, Funktionen, Enums, Makros, Seiten)
- Doku wird automatisch gefunden – passend zum Qt des Projekts über
  **qmake-tools.nvim** (qmake des aktiven Kits) bzw. **cmake-tools.nvim** (`Qt6_DIR` aus der CMakeCache)

## Voraussetzungen

- Neovim ≥ 0.10
- Python 3 (nur Standardbibliothek: `sqlite3`, `zlib`, `html.parser`)
- lokale Qt-Doku (empfohlen), z. B.
  - Qt Online-Installer / Maintenance Tool: *Qt → Qt 6.x → Additional Libraries → Qt Documentation*
    (landet in `~/Qt/Docs/Qt-6.x.y/*.qch`)
  - Debian/Ubuntu: `qt6-base-doc` (`.qch`) oder `qt6-base-doc-html`, weitere Module `qt6-*-doc`
  - Arch: `qt6-doc`, Fedora: `qt6-qtbase-doc`, Homebrew: in `qt` enthalten
- optional `curl` für die Online-Doku im Editor (sonst Browser)

Prüfen mit `:checkhealth qt-docs`.

## Installation (lazy.nvim)

```lua
{
  "dein-name/qt-docs.nvim",
  cmd = { "QtDoc", "QtDocHover", "QtDocSearch", "QtDocBrowser", "QtDocIndex" },
  ft = { "cpp", "c" },
  opts = { map_k = true },
  keys = {
    { "<leader>qk", "<cmd>QtDocHover<cr>", desc = "Qt-Doku (Hover)" },
    { "<leader>qK", "<cmd>QtDoc<cr>", desc = "Qt-Doku (Seite)" },
    { "<leader>q/", "<cmd>QtDocSearch<cr>", desc = "Qt-Doku durchsuchen" },
  },
}
```

## Befehle

| Befehl | |
|---|---|
| `:QtDoc [Stichwort]` | Seite öffnen – ohne Argument das Symbol unter dem Cursor (Tab-Vervollständigung) |
| `:QtDocHover` | Abschnitt des Symbols unter dem Cursor im Float |
| `:QtDocSearch [Präfix]` | Picker über alle Stichwörter (`vim.ui.select` – mit telescope/fzf-lua/snacks fuzzy) |
| `:QtDocBrowser [Stichwort]` | auf doc.qt.io im Browser öffnen |
| `:QtDocIndex` | Index neu erstellen (passiert sonst automatisch bei Änderungen) |

Im Doku-Buffer:

| Taste | |
|---|---|
| `<CR>` `<C-]>` `gd` | Link unter dem Cursor folgen (ohne Link: Wort nachschlagen) |
| `<BS>` `<C-o>` / `<Tab>` `<C-i>` | zurück / vor |
| `K` | Wort unter dem Cursor nachschlagen |
| `gO` | Inhaltsverzeichnis (Location-List) |
| `s` | Suche |
| `gx` | aktuellen Abschnitt im Browser öffnen |
| `q` | schließen |

## Konfiguration

```lua
require("qt-docs").setup({
  paths = {},               -- z. B. { "~/Qt/Docs/Qt-6.8.0" }; leer = automatisch
  single_version = true,    -- nur eine Qt-Version indizieren (Projekt-Qt bzw. neueste)
  python = nil,             -- Standard: python3 (Windows: python)
  window = "vsplit",        -- "float" | "split" | "vsplit" | "tab" | "current"
  float = { width = 0.8, height = 0.85, border = "rounded" },
  split_size = nil,
  hover = { max_width = 100, max_height = 30, border = "rounded" },
  map_k = false,            -- K in C/C++-Buffern: Qt-Doku, sonst LSP-Hover
  use_clangd = true,        -- Symbol über clangd-Hover auflösen
  online = {
    enabled = true,
    base_url = "https://doc.qt.io/qt-6/",  -- z. B. "https://doc.qt.io/qt-5/"
    mode = "render",        -- "render" (curl + Anzeige in Neovim) | "browser"
  },
  keys = { follow = { "<CR>", "<C-]>", "gd" }, back = { "<BS>", "<C-o>" }, ... },
  cache_dir = nil,          -- Standard: stdpath("cache")/qt-docs
})
```

### Wie die Doku gefunden wird

1. `paths` aus der Konfiguration
2. Qt des Projekts: qmake-tools.nvim (`qmake -query QT_INSTALL_DOCS` des aktiven Kits) oder
   cmake-tools.nvim (`Qt6_DIR` in der `CMakeCache.txt` → qmake bzw. `~/Qt/Docs/Qt-<Version>`)
3. `$QT_DOC_DIR`, `qmake6`/`qmake` im PATH
4. `~/Qt/Docs/Qt-*`, `/opt/Qt/Docs/Qt-*`, `C:/Qt/Docs/Qt-*`, `/usr/share/qt6/doc`, `/usr/share/qt5/doc`, Homebrew …

Der Stichwort-Index (alle Klassen, Member, Enums, Makros, Seiten) wird einmalig in
`stdpath("cache")/qt-docs` abgelegt und neu gebaut, sobald sich eine `.qch`/`.index`-Datei ändert.

## Zusammenspiel mit qt-assist.nvim

Beide Plugins teilen sich das Präfix `<leader>q`; qt-assist erzeugt Code (Getter/Setter/Q_PROPERTY,
Definitionen), qt-docs zeigt die Doku dazu.

## Tests

```sh
nvim --headless -u NONE -l tests/run.lua
# zusätzlich mit echter Doku:
QT_DOCS_TEST=/usr/share/qt6/doc nvim --headless -u NONE -l tests/run.lua
```

Die Qt-Dokumentation steht unter der GNU FDL 1.3 und ist nicht Teil dieses Repos; die Tests
verwenden selbst erzeugte Mini-Fixtures.
