if vim.g.loaded_qt_docs then
  return
end
vim.g.loaded_qt_docs = true

if vim.fn.has("nvim-0.10") == 0 then
  vim.notify("qt-docs.nvim benötigt Neovim >= 0.10", vim.log.levels.ERROR)
  return
end

local function qd()
  return require("qt-docs")
end

local cmd = vim.api.nvim_create_user_command
local function complete(arglead)
  return qd().complete(arglead)
end

cmd("QtDoc", function(o)
  qd().open(o.args)
end, { nargs = "?", complete = complete, desc = "Qt-Doku zu Stichwort / Symbol unter dem Cursor" })
cmd("QtDocHover", function()
  qd().hover()
end, { desc = "Qt-Doku des Symbols im Float" })
cmd("QtDocSearch", function(o)
  qd().search(o.args)
end, { nargs = "?", complete = complete, desc = "Qt-Doku durchsuchen" })
cmd("QtDocBrowser", function(o)
  qd().browser(o.args)
end, { nargs = "?", complete = complete, desc = "Qt-Doku im Browser öffnen" })
cmd("QtDocIndex", function()
  qd().reindex()
end, { desc = "Qt-Doku-Index neu erstellen" })
