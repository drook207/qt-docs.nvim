-- Keyword index: built by Python from the .qch/.index files and stored as
-- JSON in the cache (rebuilt as soon as a docs file changes).
local config = require("qt-docs.config")
local discover = require("qt-docs.discover")

local M = {}

local uv = vim.uv or vim.loop

M.helper = vim.fs.joinpath(
  vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h:h"), "python", "qtdoc.py")

local state = {
  data = nil, -- { sources, entries, files }
  key = nil,
  building = false,
  waiting = {},
}

--- Signature of the docs files (path + mtime + size)
local function fingerprint(paths)
  local parts = { "v1" }
  for _, p in ipairs(paths) do
    parts[#parts + 1] = p
    local st = uv.fs_stat(p)
    if st and st.type == "file" then
      parts[#parts + 1] = st.mtime.sec .. ":" .. st.size
    elseif st then
      for _, f in ipairs(vim.fn.glob(p .. "/*.qch", true, true)) do
        local s = uv.fs_stat(f)
        parts[#parts + 1] = f .. ":" .. (s and (s.mtime.sec .. ":" .. s.size) or "")
      end
      for _, f in ipairs(vim.fn.glob(p .. "/*/*.index", true, true)) do
        local s = uv.fs_stat(f)
        parts[#parts + 1] = f .. ":" .. (s and s.mtime.sec or "")
      end
    end
  end
  return vim.fn.sha256(table.concat(parts, "\n")):sub(1, 16)
end

local function prepare(data)
  data.by_key = {}
  data.by_lower = {}
  data.file_info = {}
  for i, e in ipairs(data.entries) do
    local k = e[1]
    local list = data.by_key[k]
    if not list then
      list = {}
      data.by_key[k] = list
    end
    list[#list + 1] = i
    local lk = k:lower()
    data.by_lower[lk] = data.by_lower[lk] or {}
    table.insert(data.by_lower[lk], i)
  end
  for _, f in ipairs(data.files) do
    -- [vpath, source_index (0-based), title]
    data.file_info[f[1]] = { source = data.sources[f[2] + 1], title = f[3] }
  end
  -- Filename → vpath (for links between modules, online fallback)
  data.by_basename = {}
  for vpath in pairs(data.file_info) do
    local base = vim.fs.basename(vpath)
    data.by_basename[base] = data.by_basename[base] or vpath
  end
  return data
end

local function read_json(path)
  local fh = io.open(path, "r")
  if not fh then
    return nil
  end
  local s = fh:read("*a")
  fh:close()
  local ok, data = pcall(vim.json.decode, s)
  return ok and type(data) == "table" and data or nil
end

local function finish(data, err)
  state.building = false
  state.empty = false
  if data and #(data.sources or {}) == 0 then
    data, err = nil, "no local Qt documentation found"
    state.empty = true
  end
  state.data = data and prepare(data) or nil
  local waiting = state.waiting
  state.waiting = {}
  for _, cb in ipairs(waiting) do
    cb(state.data, err)
  end
end

--- Get the index (loads the cache or rebuilds it). cb(data|nil, err)
---@param opts table|nil { force = bool, sync = bool }
function M.get(cb, opts)
  opts = opts or {}
  local paths, why = discover.paths()
  if #paths == 0 then
    cb(nil, "no local Qt documentation found")
    return
  end
  local key = fingerprint(paths)
  if state.key == key and not opts.force and not state.building then
    if state.data then
      cb(state.data)
      return
    elseif state.empty then
      cb(nil, "no local Qt documentation found")
      return
    end
  end
  table.insert(state.waiting, cb)
  if state.building then
    return
  end
  state.key = key
  local dir = config.cache_dir()
  local ok_dir = pcall(vim.fn.mkdir, dir, "p")
  if not ok_dir or vim.fn.filewritable(dir) ~= 2 then
    -- Cache not writable: use a temporary directory
    dir = vim.fs.joinpath(vim.fn.fnamemodify(vim.fn.tempname(), ":h"), "qt-docs")
    pcall(vim.fn.mkdir, dir, "p")
    if not M._warned_cache then
      M._warned_cache = true
      vim.notify("qt-docs: cache directory not writable, using " .. dir, vim.log.levels.WARN)
    end
  end
  local file = vim.fs.joinpath(dir, "index-" .. key .. ".json")
  if not opts.force and uv.fs_stat(file) then
    local data = read_json(file)
    if data then
      finish(data)
      return
    end
  end
  state.building = true
  local cmd = { config.python(), M.helper, "index", file }
  vim.list_extend(cmd, paths)
  if not opts.sync then
    vim.notify("qt-docs: building index (" .. table.concat(paths, ", ") .. ", " .. (why or "") .. ") …")
  end
  local function done(res)
    if res.code ~= 0 then
      finish(nil, "index build failed: " .. (res.stderr or ""))
      return
    end
    local data = read_json(file)
    -- clean up old indexes
    for _, f in ipairs(vim.fn.glob(vim.fs.joinpath(dir, "index-*.json"), true, true)) do
      if f ~= file then
        os.remove(f)
      end
    end
    if data then
      finish(data)
    else
      finish(nil, "index unreadable")
    end
  end
  local ok, proc = pcall(vim.system, cmd, { text = true }, (not opts.sync) and vim.schedule_wrap(done) or nil)
  if not ok then
    finish(nil, "Python cannot be started (" .. config.python() .. "): " .. tostring(proc))
    return
  end
  if opts.sync then
    done(proc:wait(60000))
  end
end

--- Synchronous (blocking) – for tests and :checkhealth
function M.get_sync(force)
  local result, err
  M.get(function(d, e)
    result, err = d, e
  end, { sync = true, force = force })
  return result, err
end

function M.loaded()
  return state.data
end

function M.reset()
  state.data, state.key, state.empty = nil, nil, false
end

-- ---------------------------------------------------------------------------
-- Search
-- ---------------------------------------------------------------------------

local function collect(data, idxs, out, seen)
  for _, i in ipairs(idxs or {}) do
    local e = data.entries[i]
    local id = e[2] .. "#" .. e[3]
    if not seen[id] then
      seen[id] = true
      out[#out + 1] = { name = e[1], vpath = e[2], anchor = e[3] }
    end
  end
end

--- Look up members via the base classes (QPushButton::setText → QAbstractButton::setText)
local function via_bases(data, cls, member, out, seen, depth)
  if depth > 12 or not data.bases then
    return
  end
  for _, base in ipairs(data.bases[cls] or {}) do
    collect(data, data.by_key[base .. "::" .. member], out, seen)
    if #out > 0 then
      return
    end
    via_bases(data, base, member, out, seen, depth + 1)
    if #out > 0 then
      return
    end
  end
end

local function strip_templates(s)
  local prev
  repeat
    prev = s
    s = s:gsub("<[^<>]*>", "")
  until s == prev
  return s
end

--- Entries for a keyword (best matches first)
---@return table[] {name, vpath, anchor}
function M.lookup(data, keyword)
  keyword = vim.trim(strip_templates(vim.trim(keyword or "")):gsub("%(.*$", ""):gsub("^::", ""))
  if keyword == "" then
    return {}
  end
  local out, seen = {}, {}
  collect(data, data.by_key[keyword], out, seen)
  if #out == 0 then
    collect(data, data.by_lower[keyword:lower()], out, seen)
  end
  local cls, member = keyword:match("^(.*)::([^:]+)$")
  if #out == 0 and cls then
    -- Constructor/destructor: QWidget::QWidget → class page, anchor "QWidget"
    local short = cls:match("([^:]+)$")
    if member == short or member == "~" .. short then
      for _, e in ipairs(M.lookup(data, cls)) do
        local anchor = member == short and short or ("dtor." .. short)
        out[#out + 1] = { name = keyword, vpath = e.vpath, anchor = anchor }
        break
      end
    end
  end
  if #out == 0 and cls then
    via_bases(data, cls, member, out, seen, 0)
  end
  if #out == 0 and cls and cls:find("::", 1, true) then
    -- Enum name in the path: Qt::AlignmentFlag::AlignLeft → Qt::AlignLeft
    local outer = cls:match("^(.*)::[^:]+$")
    collect(data, data.by_key[outer .. "::" .. member], out, seen)
  end
  if #out == 0 and keyword:find("::", 1, true) then
    -- Drop namespace prefixes: std::QString → QString, Qt::AlignLeft stays
    local parts = vim.split(keyword, "::", { plain = true })
    for i = 2, #parts - 1 do
      local k = table.concat(parts, "::", i)
      collect(data, data.by_key[k], out, seen)
    end
  end
  if #out == 0 and not keyword:find("::", 1, true) then
    -- Members of any class: "arg" → QString::arg, …
    local suffix = "::" .. keyword
    for k, idxs in pairs(data.by_key) do
      if #k > #suffix and k:sub(-#suffix) == suffix then
        collect(data, idxs, out, seen)
      end
    end
    table.sort(out, function(a, b)
      return a.name < b.name
    end)
  end
  if #out == 0 and cls and data.by_key[cls] then
    -- Unknown member: at least the class page
    collect(data, data.by_key[cls], out, seen)
    for _, e in ipairs(out) do
      e.partial = true
    end
  end
  return out
end

--- All keywords with a prefix (for completion/picker)
function M.complete(data, prefix, limit)
  prefix = (prefix or ""):lower()
  local res = {}
  limit = limit or math.huge
  for k in pairs(data.by_key) do
    if prefix == "" or k:lower():sub(1, #prefix) == prefix then
      res[#res + 1] = k
    end
  end
  table.sort(res, function(a, b)
    if #a ~= #b and (a:lower() == prefix or b:lower() == prefix) then
      return a:lower() == prefix
    end
    return a < b
  end)
  if #res > limit then
    res = vim.list_slice(res, 1, limit)
  end
  return res
end

return M
