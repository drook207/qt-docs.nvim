-- Load pages (local or online), display them, follow links, history.
local config = require("qt-docs.config")
local index = require("qt-docs.index")

local M = {}

local page_cache = {} -- vpath → page
local history = {} -- winid → { list = {}, pos = 0 }

local function notify(msg, level)
  vim.notify("qt-docs: " .. msg, level or vim.log.levels.INFO)
end

-- ---------------------------------------------------------------------------
-- Loading
-- ---------------------------------------------------------------------------

local function decode_page(res, vpath, origin)
  if res.code ~= 0 then
    return nil, (res.stderr ~= "" and res.stderr or "rendering failed")
  end
  local ok, page = pcall(vim.json.decode, res.stdout)
  if not ok or type(page) ~= "table" then
    return nil, "invalid output from the helper"
  end
  page.vpath = vpath
  page.origin = origin
  if type(page.anchors) ~= "table" or vim.tbl_isempty(page.anchors) then
    page.anchors = {}
  end
  return page
end

function M.online_url(vpath, anchor)
  local base = config.options.online.base_url
  if not base:match("/$") then
    base = base .. "/"
  end
  return base .. vim.fs.basename(vpath) .. ((anchor and anchor ~= "") and ("#" .. anchor) or "")
end

--- Load a page. cb(page|nil, err)
function M.load(data, vpath, cb)
  if page_cache[vpath] then
    cb(page_cache[vpath])
    return
  end
  local py = config.python()
  local info = data and data.file_info[vpath]
  if not info and data then
    -- Link into another module / online path: search by filename
    local alt = data.by_basename[vim.fs.basename(vpath)]
    if alt then
      vpath = alt
      info = data.file_info[alt]
      if page_cache[vpath] then
        cb(page_cache[vpath])
        return
      end
    end
  end
  local function done(res, origin)
    local page, err = decode_page(res, vpath, origin)
    if page then
      page_cache[vpath] = page
    end
    cb(page, err)
  end
  if info then
    local src = info.source
    local cmd
    if src.type == "qch" then
      cmd = { py, index.helper, "render", "qch", src.path, vpath }
    else
      cmd = { py, index.helper, "render", "file", vim.fs.joinpath(src.path, vpath), vpath }
    end
    local ok, err = pcall(vim.system, cmd, { text = true }, vim.schedule_wrap(function(res)
      done(res, "local")
    end))
    if not ok then
      cb(nil, "Python cannot be started (" .. py .. "): " .. tostring(err))
    end
    return
  end
  -- online
  local o = config.options.online
  if not o.enabled then
    cb(nil, "not in the local docs: " .. vpath)
    return
  end
  local url = M.online_url(vpath)
  if o.mode == "browser" or vim.fn.executable("curl") == 0 then
    M.open_browser(url)
    cb(nil, nil)
    return
  end
  local ok, err = pcall(vim.system, { "curl", "-sSfL", "--max-time", "15", url }, { text = true },
    vim.schedule_wrap(function(res)
      if res.code ~= 0 then
        cb(nil, "download failed: " .. url .. " " .. (res.stderr or ""))
        return
      end
      local ok2, err2 = pcall(vim.system, { py, index.helper, "render", "stdin", vim.fs.basename(vpath) },
        { text = true, stdin = res.stdout }, vim.schedule_wrap(function(r)
          done(r, "online")
        end))
      if not ok2 then
        cb(nil, "Python cannot be started (" .. py .. "): " .. tostring(err2))
      end
    end))
  if not ok then
    cb(nil, "curl cannot be started: " .. tostring(err))
  end
end

function M.open_browser(url)
  if vim.ui.open then
    vim.ui.open(url)
  else
    notify(url)
  end
end

-- ---------------------------------------------------------------------------
-- Windows and buffers
-- ---------------------------------------------------------------------------

local function find_doc_window()
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local buf = vim.api.nvim_win_get_buf(win)
    if vim.b[buf].qt_docs then
      return win
    end
  end
end

local function open_window(buf)
  local o = config.options
  local win = find_doc_window()
  if win then
    vim.api.nvim_win_set_buf(win, buf)
    vim.api.nvim_set_current_win(win)
    return win
  end
  if o.window == "float" then
    local w = math.floor(vim.o.columns * o.float.width)
    local h = math.floor((vim.o.lines - 2) * o.float.height)
    win = vim.api.nvim_open_win(buf, true, {
      relative = "editor", width = w, height = h,
      row = math.floor((vim.o.lines - h) / 2) - 1, col = math.floor((vim.o.columns - w) / 2),
      border = o.float.border, style = "minimal", title = " Qt Docs ", title_pos = "center",
    })
  else
    local size = o.split_size and tostring(o.split_size) or ""
    if o.window == "split" then
      vim.cmd(size .. "split")
    elseif o.window == "vsplit" then
      vim.cmd("vertical " .. size .. "split")
    elseif o.window == "tab" then
      vim.cmd("tab split")
    end
    win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(win, buf)
  end
  return win
end

local function setup_window(win)
  local wo = vim.wo[win]
  wo.conceallevel = 2
  wo.concealcursor = "n"
  wo.wrap = true
  wo.linebreak = true
  wo.number = false
  wo.relativenumber = false
  wo.signcolumn = "no"
  wo.foldenable = false
  wo.spell = false
  wo.list = false
end

local function map(buf, lhs_list, fn, desc)
  for _, lhs in ipairs(lhs_list or {}) do
    vim.keymap.set("n", lhs, fn, { buffer = buf, nowait = true, silent = true, desc = "qt-docs: " .. desc })
  end
end

local function buffer_for(page)
  local name = "qtdoc://" .. page.vpath
  local buf = vim.fn.bufnr(name)
  if buf == -1 or not vim.api.nvim_buf_is_valid(buf) then
    buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(buf, name)
  end
  local bo = vim.bo[buf]
  bo.modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, page.lines)
  bo.modifiable = false
  bo.modified = false
  bo.buftype = "nofile"
  bo.bufhidden = "hide"
  bo.swapfile = false
  vim.b[buf].qt_docs = page.vpath
  if bo.filetype ~= "markdown" then
    bo.filetype = "markdown"
  end
  pcall(vim.treesitter.start, buf, "markdown")
  local k = config.options.keys
  map(buf, k.follow, M.follow, "follow link")
  map(buf, k.back, function()
    M.history_move(-1)
  end, "back")
  map(buf, k.forward, function()
    M.history_move(1)
  end, "forward")
  map(buf, k.close, function()
    local win = vim.api.nvim_get_current_win()
    if #vim.api.nvim_tabpage_list_wins(0) > 1 then
      vim.api.nvim_win_close(win, false)
    else
      vim.cmd("bprevious")
    end
  end, "close")
  map(buf, k.browser, function()
    local line = vim.api.nvim_win_get_cursor(0)[1]
    local anchor = M.anchor_at(page, line)
    M.open_browser(M.online_url(page.vpath, anchor))
  end, "open in browser")
  map(buf, k.search, function()
    require("qt-docs").search()
  end, "search")
  map(buf, k.toc, function()
    M.toc(buf)
  end, "table of contents")
  map(buf, k.lookup, function()
    require("qt-docs").open(vim.fn.expand("<cword>"))
  end, "look up keyword")
  return buf
end

--- Next anchor above a line (for gx)
function M.anchor_at(page, line)
  local best, best_line = nil, 0
  for a, l in pairs(page.anchors) do
    if l <= line and l > best_line then
      best, best_line = a, l
    end
  end
  return best
end

local function anchor_line(page, anchor, name)
  if not anchor or anchor == "" then
    return 1
  end
  local l = page.anchors[anchor] or page.anchors[anchor .. "x"]
  if l then
    return l
  end
  -- Fallback: heading with the qualified name (QScreen::geometryChanged)
  if name and name:find("::", 1, true) then
    for i, line in ipairs(page.lines) do
      if line:match("^#+ ") and (line:find(name .. "(", 1, true) or line:find(name .. " :", 1, true)
          or line:match(vim.pesc(name) .. "%s*$")) then
        return i
      end
    end
  end
  -- then: heading whose function name exactly matches the anchor
  local base = anchor:gsub("%-[%w]*$", "")
  for i, line in ipairs(page.lines) do
    if line:match("^#+ ") and line:find("%f[%w_]" .. vim.pesc(base) .. "%f[^%w_]") then
      return i
    end
  end
  return 1
end
M.anchor_line = anchor_line

local function push_history(win, item, prev_line)
  local h = history[win] or { list = {}, pos = 0 }
  history[win] = h
  -- Remember the position of the previously displayed page
  local cur = h.list[h.pos]
  if cur and prev_line then
    cur.line = prev_line
  end
  for i = #h.list, h.pos + 1, -1 do
    h.list[i] = nil
  end
  h.list[#h.list + 1] = item
  h.pos = #h.list
end

--- Display a page
---@param opts table|nil { anchor, line, no_history, win }
function M.show(page, opts)
  opts = opts or {}
  -- Cursor of the previously displayed page (for the history)
  local prev_win = (opts.win and vim.api.nvim_win_is_valid(opts.win)) and opts.win or find_doc_window()
  local prev_line = prev_win and vim.b[vim.api.nvim_win_get_buf(prev_win)].qt_docs
    and vim.api.nvim_win_get_cursor(prev_win)[1] or nil
  local buf = buffer_for(page)
  local win = opts.win
  if win and vim.api.nvim_win_is_valid(win) then
    vim.api.nvim_win_set_buf(win, buf)
    vim.api.nvim_set_current_win(win)
  else
    win = open_window(buf)
  end
  setup_window(win)
  local line = opts.line or anchor_line(page, opts.anchor, opts.name)
  line = math.max(1, math.min(line, vim.api.nvim_buf_line_count(buf)))
  vim.api.nvim_win_set_cursor(win, { line, 0 })
  vim.api.nvim_win_call(win, function()
    vim.cmd("normal! zt")
  end)
  if not opts.no_history then
    push_history(win, { vpath = page.vpath, anchor = opts.anchor, line = line }, prev_line)
  end
  return buf, win
end

--- Open vpath(+anchor)
function M.open(vpath, anchor, opts)
  index.get(function(data)
    M.load(data, vpath, function(page, err)
      if not page then
        if err then
          notify(err, vim.log.levels.WARN)
        end
        return
      end
      M.show(page, vim.tbl_extend("force", opts or {}, { anchor = anchor }))
    end)
  end)
end

function M.history_move(delta)
  local win = vim.api.nvim_get_current_win()
  local h = history[win]
  if not h then
    return
  end
  local target = h.pos + delta
  if target < 1 or target > #h.list then
    return
  end
  local cur = h.list[h.pos]
  if cur then
    cur.line = vim.api.nvim_win_get_cursor(win)[1]
  end
  h.pos = target
  local item = h.list[target]
  index.get(function(data)
    M.load(data, item.vpath, function(page)
      if page then
        M.show(page, { line = item.line, win = win, no_history = true })
      end
    end)
  end)
end

--- Markdown link under (or nearest to) the cursor
function M.link_at_cursor()
  local line = vim.api.nvim_get_current_line()
  local col = vim.api.nvim_win_get_cursor(0)[2] + 1
  local best
  local init = 1
  while true do
    local s, e, _, target = line:find("%[([^%]]*)%]%(([^%)%s]+)%)", init)
    if not s then
      break
    end
    if col >= s and col <= e then
      best = target
      break
    end
    init = e + 1
  end
  return best
end

function M.follow()
  local target = M.link_at_cursor()
  if not target then
    -- no link: look up the word
    require("qt-docs").open(vim.fn.expand("<cword>"))
    return
  end
  target = target:gsub("%%20", " "):gsub("%%29", ")")
  local buf = vim.api.nvim_get_current_buf()
  local cur = vim.b[buf].qt_docs
  local win = vim.api.nvim_get_current_win()
  if target:match("^#") then
    M.open(cur, target:sub(2), { win = win })
    return
  end
  if target:match("^https?://") then
    -- open doc.qt.io links locally when possible
    local file, anchor = target:match("^https?://doc%.qt%.io/[^/]+/([^#?]+%.html)#?(.*)$")
    local data = index.loaded()
    if file and data and data.by_basename[file] then
      M.open(data.by_basename[file], anchor, { win = win })
    else
      M.open_browser(target)
    end
    return
  end
  local vpath, anchor = target:match("^([^#]+)#?(.*)$")
  M.open(vpath, anchor, { win = win })
end

--- Headings into the location list
function M.toc(buf)
  local items = {}
  for i, l in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
    local hashes, text = l:match("^(#+) (.*)$")
    if hashes and #hashes <= 3 then
      items[#items + 1] = { bufnr = buf, lnum = i, col = 1, text = string.rep("  ", #hashes - 1) .. text }
    end
  end
  vim.fn.setloclist(0, items, "r")
  vim.fn.setloclist(0, {}, "a", { title = "Qt Docs: Contents" })
  vim.cmd("lopen")
end

--- Section around an anchor (for the hover); overloads directly after it
--- are shown as well (max. `max_overloads`)
function M.section(page, anchor, name, max_overloads)
  local lines = page.lines
  local start = anchor_line(page, anchor, name)
  local res = {}
  if not anchor or anchor == "" then
    -- Class page: up to the second main heading (title, short description, header info)
    for i = 1, #lines do
      if i > 1 and lines[i]:match("^## ") then
        break
      end
      res[#res + 1] = lines[i]
    end
    return res
  end
  local level = (lines[start] or ""):match("^(#+) ")
  level = level and #level or 6
  -- "QString::arg(" – same function in the following headings = overload
  local sig = (lines[start] or ""):match("([%w_:~]+::[%w_~]+)%(")
  local overloads = 0
  max_overloads = max_overloads or 8
  for i = start, #lines do
    local h = lines[i]:match("^(#+) ")
    if i > start and h and #h <= level then
      if sig and #h == level and lines[i]:find(sig .. "(", 1, true) and overloads < max_overloads then
        overloads = overloads + 1
        res[#res + 1] = "---"
        res[#res + 1] = ""
      else
        break
      end
    end
    res[#res + 1] = lines[i]
  end
  while #res > 0 and res[#res] == "" do
    res[#res] = nil
  end
  return res
end

function M.clear_cache()
  page_cache = {}
end

return M
