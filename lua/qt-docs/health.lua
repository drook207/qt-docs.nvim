local M = {}

function M.check()
  local h = vim.health
  local config = require("qt-docs.config")
  local discover = require("qt-docs.discover")
  local index = require("qt-docs.index")

  h.start("qt-docs")
  if vim.fn.has("nvim-0.10") == 1 then
    h.ok("Neovim >= 0.10")
  else
    h.error("Neovim >= 0.10 required")
  end

  local py = config.python()
  local res = vim.fn.executable(py) == 1
    and vim.system({ py, "-c", "import sqlite3, zlib, html.parser, json; print('ok')" }, { text = true }):wait(5000)
  if res and res.code == 0 then
    h.ok("Python: " .. vim.fn.exepath(py) .. " (sqlite3, zlib available)")
  else
    h.error("Python 3 with sqlite3/zlib not found (" .. py .. ")", { "set python = '/path/to/python3'" })
  end

  if vim.fn.executable("curl") == 1 then
    h.ok("curl available (online docs are displayed in Neovim)")
  else
    h.info("curl missing – online docs open in the browser")
  end

  local paths, why = discover.paths()
  if #paths == 0 then
    h.warn("no local Qt documentation found", {
      "install Qt docs (Maintenance Tool: »Qt <Version> → Additional Libraries/Documentation«,",
      "  Debian/Ubuntu: qt6-base-doc / qt6-documentation-tools, Arch: qt6-doc)",
      "or set paths = { '~/Qt/Docs/Qt-6.8.0' }",
      config.options.online.enabled and "until then the online docs are used" or "",
    })
    return
  end
  for _, p in ipairs(paths) do
    h.ok("Docs: " .. p .. " (" .. (why or "") .. ")")
  end
  local data, err = index.get_sync()
  if data then
    h.ok(("Index: %d keywords, %d pages, %d sources"):format(#data.entries, #data.files, #data.sources))
  else
    h.error("Index: " .. tostring(err))
  end
end

return M
