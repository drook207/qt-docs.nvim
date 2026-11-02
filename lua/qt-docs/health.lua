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
    h.error("Neovim >= 0.10 benötigt")
  end

  local py = config.python()
  local res = vim.fn.executable(py) == 1
    and vim.system({ py, "-c", "import sqlite3, zlib, html.parser, json; print('ok')" }, { text = true }):wait(5000)
  if res and res.code == 0 then
    h.ok("Python: " .. vim.fn.exepath(py) .. " (sqlite3, zlib vorhanden)")
  else
    h.error("Python 3 mit sqlite3/zlib nicht gefunden (" .. py .. ")", { "python = '/pfad/zu/python3' setzen" })
  end

  if vim.fn.executable("curl") == 1 then
    h.ok("curl vorhanden (Online-Doku wird in Neovim angezeigt)")
  else
    h.info("curl fehlt – Online-Doku öffnet im Browser")
  end

  local paths, why = discover.paths()
  if #paths == 0 then
    h.warn("keine lokale Qt-Dokumentation gefunden", {
      "Qt-Doku installieren (Maintenance Tool: »Qt <Version> → Additional Libraries/Documentation«,",
      "  Debian/Ubuntu: qt6-base-doc / qt6-documentation-tools, Arch: qt6-doc)",
      "oder paths = { '~/Qt/Docs/Qt-6.8.0' } setzen",
      config.options.online.enabled and "bis dahin wird die Online-Doku verwendet" or "",
    })
    return
  end
  for _, p in ipairs(paths) do
    h.ok("Doku: " .. p .. " (" .. (why or "") .. ")")
  end
  local data, err = index.get_sync()
  if data then
    h.ok(("Index: %d Stichwörter, %d Seiten, %d Quellen"):format(#data.entries, #data.files, #data.sources))
  else
    h.error("Index: " .. tostring(err))
  end
end

return M
