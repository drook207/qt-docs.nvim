# qt-docs.nvim

Read the Qt documentation directly in Neovim – offline from the `.qch` files or the
HTML docs of your Qt installation, with an online fallback to doc.qt.io.

- `:QtDoc` on `str.arg(…)` opens **QString::arg** – the symbol is resolved via clangd
  (method → class, variable → its type, enum value → `Qt::AlignLeft`)
- Hover float with only the matching section (like `K`), optionally as a `K` replacement:
  Qt docs if the symbol is in the docs, otherwise normal LSP hover
- Pages as Markdown (headings, code blocks with C++ highlighting, tables, links),
  works with render-markdown.nvim / markview.nvim
- Follow links (also into other modules and doc.qt.io links locally), history back/forward,
  table of contents, search across all keywords (classes, functions, enums, macros, pages)
- Docs are found automatically – matching the project's Qt via
  **qmake-tools.nvim** (active kit's qmake) or **cmake-tools.nvim** (`Qt6_DIR` from the CMakeCache)

## Requirements

- Neovim ≥ 0.10
- Python 3 (standard library only: `sqlite3`, `zlib`, `html.parser`)
- local Qt docs (recommended), e.g.
  - Qt Online Installer / Maintenance Tool: *Qt → Qt 6.x → Additional Libraries → Qt Documentation*
    (ends up in `~/Qt/Docs/Qt-6.x.y/*.qch`)
  - Debian/Ubuntu: `qt6-base-doc` (`.qch`) or `qt6-base-doc-html`, further modules `qt6-*-doc`
  - Arch: `qt6-doc`, Fedora: `qt6-qtbase-doc`, Homebrew: included in `qt`
- optional `curl` for the online docs in the editor (otherwise browser)

Check with `:checkhealth qt-docs`.

## Installation (lazy.nvim / LazyVim)

```lua
return {
  {
    "drook207/qt-docs.nvim",
    -- local checkout instead: dir = "~/Projects/qt-docs.nvim",
    name = "qt-docs.nvim",
    ft = { "cpp", "c", "objcpp" },
    cmd = { "QtDoc", "QtDocHover", "QtDocSearch", "QtDocBrowser", "QtDocIndex" },
    dependencies = {
      -- optional: find the docs matching the project's Qt
      { "Civitasv/cmake-tools.nvim", optional = true },
      { "drook207/qmake-tools.nvim", optional = true },
    },
    opts = {
      -- paths = { "~/Qt/Docs/Qt-6.8.0" }, -- empty = search automatically
      window = "vsplit", -- "float" | "split" | "vsplit" | "tab" | "current"
      map_k = true, -- K: Qt docs if available, otherwise LSP hover
      online = {
        enabled = true,
        base_url = "https://doc.qt.io/qt-6/",
        mode = "render", -- or "browser"
      },
    },
    keys = {
      { "<leader>qk", "<cmd>QtDocHover<cr>", desc = "Qt docs: hover" },
      { "<leader>qK", "<cmd>QtDoc<cr>", desc = "Qt docs: open page" },
      { "<leader>q/", "<cmd>QtDocSearch<cr>", desc = "Qt docs: search" },
      { "<leader>qb", "<cmd>QtDocBrowser<cr>", desc = "Qt docs: in browser" },
    },
  },
}
```

## Commands

| Command | |
|---|---|
| `:QtDoc [keyword]` | Open page – without argument the symbol under the cursor (tab completion) |
| `:QtDocHover` | Section of the symbol under the cursor in a float |
| `:QtDocSearch [prefix]` | Picker over all keywords (`vim.ui.select` – fuzzy with telescope/fzf-lua/snacks) |
| `:QtDocBrowser [keyword]` | Open on doc.qt.io in the browser |
| `:QtDocIndex` | Rebuild the index (otherwise happens automatically on changes) |

In the doc buffer:

| Key | |
|---|---|
| `<CR>` `<C-]>` `gd` | Follow link under the cursor (without a link: look up the word) |
| `<BS>` `<C-o>` / `<Tab>` `<C-i>` | back / forward |
| `K` | Look up the word under the cursor |
| `gO` | Table of contents (location list) |
| `s` | Search |
| `gx` | Open the current section in the browser |
| `q` | close |

## Configuration

```lua
require("qt-docs").setup({
  paths = {},               -- e.g. { "~/Qt/Docs/Qt-6.8.0" }; empty = automatic
  single_version = true,    -- index only one Qt version (project Qt or newest)
  python = nil,             -- default: python3 (Windows: python)
  window = "vsplit",        -- "float" | "split" | "vsplit" | "tab" | "current"
  float = { width = 0.8, height = 0.85, border = "rounded" },
  split_size = nil,
  hover = { max_width = 100, max_height = 30, border = "rounded" },
  map_k = false,            -- K in C/C++ buffers: Qt docs, otherwise LSP hover
  use_clangd = true,        -- resolve symbol via clangd hover
  online = {
    enabled = true,
    base_url = "https://doc.qt.io/qt-6/",  -- e.g. "https://doc.qt.io/qt-5/"
    mode = "render",        -- "render" (curl + display in Neovim) | "browser"
  },
  keys = { follow = { "<CR>", "<C-]>", "gd" }, back = { "<BS>", "<C-o>" }, ... },
  cache_dir = nil,          -- default: stdpath("cache")/qt-docs
})
```

### How the docs are found

1. `paths` from the configuration
2. Project Qt: qmake-tools.nvim (`qmake -query QT_INSTALL_DOCS` of the active kit) or
   cmake-tools.nvim (`Qt6_DIR` in `CMakeCache.txt` → qmake or `~/Qt/Docs/Qt-<version>`)
3. `$QT_DOC_DIR`, `qmake6`/`qmake` in PATH
4. `~/Qt/Docs/Qt-*`, `/opt/Qt/Docs/Qt-*`, `C:/Qt/Docs/Qt-*`, `/usr/share/qt6/doc`, `/usr/share/qt5/doc`, Homebrew …

The keyword index (all classes, members, enums, macros, pages) is stored once in
`stdpath("cache")/qt-docs` and rebuilt as soon as a `.qch`/`.index` file changes.

## Interaction with qt-assist.nvim

Both plugins share the `<leader>q` prefix; qt-assist generates code (getters/setters/Q_PROPERTY,
definitions), qt-docs shows the matching docs.

## Tests

```sh
nvim --headless -u NONE -l tests/run.lua
# additionally with real docs:
QT_DOCS_TEST=/usr/share/qt6/doc nvim --headless -u NONE -l tests/run.lua
```

The Qt documentation is under the GNU FDL 1.3 and is not part of this repo; the tests
use self-generated mini fixtures.
