local config = require("qt-docs.config")
local index = require("qt-docs.index")
local viewer = require("qt-docs.viewer")
local symbol = require("qt-docs.symbol")

local M = {}

local function notify(msg, level)
  vim.notify("qt-docs: " .. msg, level or vim.log.levels.INFO)
end

--- Online-Ziel raten, wenn keine lokale Doku vorhanden ist: QString::arg → qstring.html#arg
local function online_guess(keyword)
  local cls, member = keyword:match("^([%w_:]-)::([%w_~]+)$")
  if not cls then
    cls = keyword
  end
  local page = cls:gsub("::", "-"):lower() .. ".html"
  return page, member
end

--- Treffer auswählen und öffnen
local function choose(entries, cb, prompt)
  if #entries == 1 then
    cb(entries[1])
    return
  end
  -- gleiche Seite+Name mehrfach (Überladungen): erste nehmen, wenn alle gleich heißen
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
    prompt = prompt or "Qt-Doku",
    format_item = function(e)
      return e.name .. "  (" .. vim.fs.basename(e.vpath) .. ")"
    end,
  }, function(e)
    if e then
      cb(e)
    end
  end)
end

--- Stichwörter nacheinander probieren
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

--- Doku öffnen. keyword: String oder nil (Symbol unter dem Cursor)
function M.open(keyword, opts)
  local keywords
  if keyword and keyword ~= "" then
    keywords = { keyword }
  else
    keywords = symbol.candidates()
  end
  if #keywords == 0 then
    notify("kein Stichwort")
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
      notify("nichts gefunden für " .. table.concat(keywords, ", "), vim.log.levels.WARN)
      return
    end
    if not config.options.online.enabled then
      notify("keine lokale Doku und Online-Doku deaktiviert", vim.log.levels.WARN)
      return
    end
    if data then
      -- lokale Doku vorhanden, aber Stichwort unbekannt: nicht raten
      notify("nichts gefunden für " .. table.concat(keywords, ", ") .. " – :QtDocSearch zum Suchen",
        vim.log.levels.WARN)
      return
    end
    local page, anchor = online_guess(k)
    viewer.open(page, anchor, opts)
  end)
end

--- Nur den Abschnitt im Float (wie LSP-Hover). Gibt false zurück, wenn nichts gefunden.
---@param fallback fun()|nil wird aufgerufen, wenn das Symbol nicht in der Doku steht
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
        notify("nichts gefunden für " .. table.concat(keywords, ", "))
      end
      return
    end
    local e = entries[1]
    viewer.load(data, e.vpath, function(page, err)
      if not page then
        notify(err or "Laden fehlgeschlagen", vim.log.levels.WARN)
        return
      end
      local lines = viewer.section(page, e.anchor, e.name)
      if #entries > 1 then
        local more = {}
        for i = 2, math.min(#entries, 6) do
          more[#more + 1] = entries[i].name
        end
        lines[#lines + 1] = ""
        lines[#lines + 1] = "_Weitere Treffer: " .. table.concat(more, ", ") .. "_"
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

--- K-Ersatz: Qt-Doku, sonst LSP-Hover
function M.k()
  M.hover(function()
    vim.lsp.buf.hover()
  end)
end

local function is_default_select()
  local info = debug.getinfo(vim.ui.select, "S")
  return info and info.source and info.source:find("vim/ui.lua", 1, true) ~= nil
end

--- Suche/Picker über alle Stichwörter
function M.search(prefix)
  index.get(function(data, err)
    if not data then
      notify(err or "kein Index", vim.log.levels.WARN)
      return
    end
    local limit = is_default_select() and 300 or nil
    local items = index.complete(data, prefix, limit)
    if #items == 0 then
      notify("nichts gefunden für " .. (prefix or ""))
      return
    end
    if limit and #items == limit then
      notify(("nur die ersten %d Treffer – Präfix angeben (:QtDocSearch QStr) oder einen Picker wie "
        .. "telescope/fzf-lua/snacks für vim.ui.select einrichten"):format(limit))
    end
    vim.ui.select(items, { prompt = "Qt-Doku" }, function(choice)
      if choice then
        M.open(choice)
      end
    end)
  end)
end

--- Im Browser öffnen
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

--- Index neu bauen
function M.reindex()
  index.reset()
  viewer.clear_cache()
  index.get(function(data, err)
    if data then
      notify(("Index: %d Stichwörter aus %d Quellen"):format(#data.entries, #data.sources))
    else
      notify(err or "Fehler", vim.log.levels.ERROR)
    end
  end, { force = true })
end

--- Vervollständigung für :QtDoc
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
        vim.keymap.set("n", "K", M.k, { buffer = ev.buf, desc = "Qt-Doku / LSP-Hover" })
      end,
    })
  end
end

return M
