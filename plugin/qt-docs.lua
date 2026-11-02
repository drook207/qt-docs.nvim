if vim.g.loaded_qt_docs then
  return
end
vim.g.loaded_qt_docs = true

if vim.fn.has("nvim-0.10") == 0 then
  vim.notify("qt-docs.nvim requires Neovim >= 0.10", vim.log.levels.ERROR)
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
end, { nargs = "?", complete = complete, desc = "Qt docs for keyword / symbol under the cursor" })
cmd("QtDocHover", function()
  qd().hover()
end, { desc = "Qt docs for the symbol in a float" })
cmd("QtDocSearch", function(o)
  qd().search(o.args)
end, { nargs = "?", complete = complete, desc = "Search Qt docs" })
cmd("QtDocBrowser", function(o)
  qd().browser(o.args)
end, { nargs = "?", complete = complete, desc = "Open Qt docs in the browser" })
cmd("QtDocIndex", function()
  qd().reindex()
end, { desc = "Rebuild the Qt docs index" })
