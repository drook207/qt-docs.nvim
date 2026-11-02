local M = {}

M.defaults = {
  -- Doc directories or .qch files. Empty = search automatically
  -- (qmake -query QT_INSTALL_DOCS, qmake-tools/cmake-tools kit, ~/Qt/Docs/Qt-*, /usr/share/qt6/doc, …)
  paths = {},
  -- When multiple Qt versions are found: use only the best one (matching the project
  -- or the newest). false = index all found versions.
  single_version = true,
  -- Python 3 (for .qch and HTML → Markdown)
  python = nil, -- nil = "python3", on Windows "python"
  -- Display: "float" | "split" | "vsplit" | "tab" | "current"
  window = "vsplit",
  float = { width = 0.8, height = 0.85, border = "rounded" },
  split_size = nil, -- width/height of the split (nil = half)
  -- Hover (:QtDocHover / K): show only the symbol's section in the float
  hover = { max_width = 100, max_height = 30, border = "rounded" },
  -- K in C++ buffers: Qt docs if the symbol is in the docs, otherwise
  -- vim.lsp.buf.hover()
  map_k = false,
  -- Resolve the symbol under the cursor via clangd (hover): str.arg() → QString::arg
  use_clangd = true,
  -- Online docs when nothing is found locally
  online = {
    enabled = true,
    base_url = "https://doc.qt.io/qt-6/",
    -- "render": fetch via curl and display in Neovim, "browser": open in the browser
    mode = "render",
  },
  -- Key mappings in the doc buffer
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
