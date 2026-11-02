local M = {}

M.defaults = {
  -- Doku-Verzeichnisse oder .qch-Dateien. Leer = automatisch suchen
  -- (qmake -query QT_INSTALL_DOCS, qmake-tools/cmake-tools-Kit, ~/Qt/Docs/Qt-*, /usr/share/qt6/doc, …)
  paths = {},
  -- Bei mehreren gefundenen Qt-Versionen: nur die beste (passend zum Projekt bzw.
  -- die neueste) verwenden. false = alle gefundenen indizieren.
  single_version = true,
  -- Python 3 (für .qch und HTML → Markdown)
  python = nil, -- nil = "python3", unter Windows "python"
  -- Anzeige: "float" | "split" | "vsplit" | "tab" | "current"
  window = "vsplit",
  float = { width = 0.8, height = 0.85, border = "rounded" },
  split_size = nil, -- Breite/Höhe des Splits (nil = Hälfte)
  -- Hover (:QtDocHover / K): nur den Abschnitt des Symbols im Float zeigen
  hover = { max_width = 100, max_height = 30, border = "rounded" },
  -- K in C++-Buffern: Qt-Doku, falls das Symbol in der Doku steht, sonst
  -- vim.lsp.buf.hover()
  map_k = false,
  -- Symbol unter dem Cursor über clangd (Hover) auflösen: str.arg() → QString::arg
  use_clangd = true,
  -- Online-Doku, wenn lokal nichts gefunden wird
  online = {
    enabled = true,
    base_url = "https://doc.qt.io/qt-6/",
    -- "render": per curl laden und in Neovim anzeigen, "browser": im Browser öffnen
    mode = "render",
  },
  -- Tastenbelegung im Doku-Buffer
  keys = {
    follow = { "<CR>", "<C-]>", "gd" },
    back = { "<BS>", "<C-o>" },
    forward = { "<C-i>", "<Tab>" },
    close = { "q" },
    browser = { "gx" },
    search = { "s" },
    toc = { "gO" },
    lookup = { "K" },
  },
  cache_dir = nil, -- nil = stdpath("cache")/qt-docs
}

M.options = vim.deepcopy(M.defaults)

function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts or {})
  if opts and opts.paths then
    M.options.paths = opts.paths
  end
  if opts and opts.keys then
    for k, v in pairs(opts.keys) do
      M.options.keys[k] = v
    end
  end
  return M.options
end

function M.python()
  if M.options.python then
    return M.options.python
  end
  if vim.fn.has("win32") == 1 then
    return vim.fn.executable("python") == 1 and "python" or "py"
  end
  return "python3"
end

function M.cache_dir()
  return M.options.cache_dir or vim.fs.joinpath(vim.fn.stdpath("cache"), "qt-docs")
end

return M
