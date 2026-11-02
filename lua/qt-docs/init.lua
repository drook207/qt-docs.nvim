local config = require("qt-docs.config")
local index = require("qt-docs.index")
local viewer = require("qt-docs.viewer")
local symbol = require("qt-docs.symbol")

local M = {}

local function notify(msg, level)
  vim.notify("qt-docs: " .. msg, level or vim.log.levels.INFO)
end

--- Guess the online target when no local docs exist: QString::arg → qstring.html#arg
local function online_guess(keyword)
  local cls, member = keyword:match("^([%w_:]-)::([%w_~]+)$")
  if not cls then
    cls = keyword
  end
  local page = cls:gsub("::", "-"):lower() .. ".html"
  return page, member
end

--- Select and open a match
local function choose(entries, cb, prompt)
  if #entries == 1 then
    cb(entries[1])
    return
  end
  -- Same page+name repeated (overloads): take the first if they all have the same name
  local same = true
  for _, e in ipairs(entries) do
    if e.name ~= entries[1].name or e.vpath ~= entries[1].vpath then
      same = false
    end
  end
  if same then
    cb(entries[1])
    return
  end
  vim.ui.select(entries, {
    prompt = prompt or "Qt docs",
    format_item = function(e)
      return e.name .. "  (" .. vim.fs.basename(e.vpath) .. ")"
    end,
  }, function(e)
    if e then
      cb(e)
    end
  end)
end

--- Try keywords one after another
---@param keywords string[]
---@param cb fun(entries: table[]|nil, data: table|nil, keyword: string|nil)
function M.resolve(keywords, cb)
  index.get(function(data)
    if data then
      for _, k in ipairs(keywords) do
        local entries = index.lookup(data, k)
        if #entries > 0 then
          cb(entries, data, k)
          return
        end
      end
    end
    cb(nil, data, keywords[1])
  end)
end

--- Open docs. keyword: string or nil (symbol under the cursor)
function M.open(keyword, opts)
  local keywords
  if keyword and keyword ~= "" then
    keywords = { keyword }
  else
    keywords = symbol.candidates()
  end
  if #keywords == 0 then
    notify("no keyword")
    return
  end
  M.resolve(keywords, function(entries, data, k)
    if entries then
      choose(entries, function(e)
        viewer.open(e.vpath, e.anchor, vim.tbl_extend("force", opts or {}, { name = e.name }))
      end)
      return
    end
    if data and not config.options.online.enabled then
      notify("nothing found for " .. table.concat(keywords, ", "), vim.log.levels.WARN)
      return
    end
    if not config.options.online.enabled then
      notify("no local docs and online docs disabled", vim.log.levels.WARN)
      return
    end
    if data then
      -- local docs available, but keyword unknown: do not guess
      notify("nothing found for " .. table.concat(keywords, ", ") .. " – :QtDocSearch to search",
        vim.log.levels.WARN)
      return
    end
    local page, anchor = online_guess(k)
    viewer.open(page, anchor, opts)
  end)
end

--- Only the section in the float (like LSP hover). Returns false if nothing is found.
---@param fallback fun()|nil called when the symbol is not in the docs
function M.hover(fallback)
  local keywords = symbol.candidates()
  if #keywords == 0 then
    if fallback then
      fallback()
    end
    return
  end
  M.resolve(keywords, function(entries, data)
    if not entries then
      if fallback then
        fallback()
      else
        notify("nothing found for " .. table.concat(keywords, ", "))
      end
      return
    end
    local e = entries[1]
    viewer.load(data, e.vpath, function(page, err)
      if not page then
        notify(err or "failed to load", vim.log.levels.WARN)
        return
      end
      local lines = viewer.section(page, e.anchor, e.name)
      if #entries > 1 then
        local more = {}
        for i = 2, math.min(#entries, 6) do
          more[#more + 1] = entries[i].name
        end
        lines[#lines + 1] = ""
        lines[#lines + 1] = "_More matches: " .. table.concat(more, ", ") .. "_"
      end
      local h = config.options.hover
      vim.lsp.util.open_floating_preview(lines, "markdown", {
        border = h.border,
        max_width = h.max_width,
        max_height = h.max_height,
        focus_id = "qt-docs-hover",
        wrap = true,
      })
    end)
  end)
end

--- K replacement: Qt docs, otherwise LSP hover
function M.k()
  M.hover(function()
    vim.lsp.buf.hover()
  end)
end

local function is_default_select()
  local info = debug.getinfo(vim.ui.select, "S")
  return info and info.source and info.source:find("vim/ui.lua", 1, true) ~= nil
end

--- Search/picker over all keywords
function M.search(prefix)
  index.get(function(data, err)
    if not data then
      notify(err or "no index", vim.log.levels.WARN)
      return
    end
    local limit = is_default_select() and 300 or nil
    local items = index.complete(data, prefix, limit)
    if #items == 0 then
      notify("nothing found for " .. (prefix or ""))
      return
    end
    if limit and #items == limit then
      notify(("only the first %d matches – specify a prefix (:QtDocSearch QStr) or set up a picker such as "
        .. "telescope/fzf-lua/snacks for vim.ui.select"):format(limit))
    end
    vim.ui.select(items, { prompt = "Qt docs" }, function(choice)
      if choice then
        M.open(choice)
      end
    end)
  end)
end

--- Open in the browser
function M.browser(keyword)
  local keywords = (keyword and keyword ~= "") and { keyword } or symbol.candidates()
  M.resolve(keywords, function(entries, _, k)
    if entries then
      choose(entries, function(e)
        viewer.open_browser(viewer.online_url(e.vpath, e.anchor))
      end)
    else
      local page, anchor = online_guess(k or "")
      viewer.open_browser(viewer.online_url(page, anchor))
    end
  end)
end

--- Rebuild the index
function M.reindex()
  index.reset()
  viewer.clear_cache()
  index.get(function(data, err)
    if data then
      notify(("Index: %d keywords from %d sources"):format(#data.entries, #data.sources))
    else
      notify(err or "error", vim.log.levels.ERROR)
    end
  end, { force = true })
end

--- Completion for :QtDoc
function M.complete(arglead)
  local data = index.loaded()
  if not data then
    return {}
  end
  return index.complete(data, arglead, 200)
end

function M.setup(opts)
  config.setup(opts)
  local group = vim.api.nvim_create_augroup("qt-docs", { clear = true })
  if config.options.map_k then
    vim.api.nvim_create_autocmd("FileType", {
      group = group,
      pattern = { "cpp", "c", "objcpp", "qml", "qmljs" },
      callback = function(ev)
        vim.keymap.set("n", "K", M.k, { buffer = ev.buf, desc = "Qt docs / LSP hover" })
      end,
    })
  end
end

return M
