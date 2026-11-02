-- Qt-Dokumentation auf dem System finden.
local config = require("qt-docs.config")

local M = {}

local uv = vim.uv or vim.loop
local is_win = vim.fn.has("win32") == 1

local function isdir(p)
  local st = p and uv.fs_stat(p)
  return st and st.type == "directory"
end

--- Enthält das Verzeichnis Doku (.qch oder Modul-Ordner mit *.index)?
function M.has_docs(dir)
  if not isdir(dir) then
    return false
  end
  local handle = uv.fs_scandir(dir)
  if not handle then
    return false
  end
  while true do
    local name, typ = uv.fs_scandir_next(handle)
    if not name then
      break
    end
    if name:match("%.qch$") then
      return true
    end
    if typ == "directory" then
      local sub = vim.fs.joinpath(dir, name)
      if vim.fn.glob(sub .. "/*.index") ~= "" then
        return true
      end
    end
  end
  return false
end

local query_cache = {}

--- qmake -query QT_INSTALL_DOCS
local function qmake_docs(qmake)
  if not qmake or qmake == "" then
    return nil
  end
  if query_cache[qmake] ~= nil then
    return query_cache[qmake] or nil
  end
  local ok, res = pcall(function()
    return vim.system({ qmake, "-query", "QT_INSTALL_DOCS" }, { text = true }):wait(5000)
  end)
  local dir = ok and res.code == 0 and vim.trim(res.stdout) or ""
  query_cache[qmake] = dir ~= "" and vim.fs.normalize(dir) or false
  return query_cache[qmake] or nil
end

--- Version aus einem Pfad wie ~/Qt/6.8.0/gcc_64 oder Qt-6.8.0
local function version_of(path)
  return path and (path:match("Qt%-(%d+%.%d+%.%d+)") or path:match("/(%d+%.%d+%.%d+)/")) or nil
end

local function version_key(v)
  local a, b, c = (v or "0.0.0"):match("(%d+)%.(%d+)%.?(%d*)")
  return (tonumber(a) or 0) * 1000000 + (tonumber(b) or 0) * 1000 + (tonumber(c) or 0)
end

--- Projekt-Qt über qmake-tools.nvim (qmake des aktiven Kits)
local function from_qmake_tools()
  local ok, qt = pcall(require, "qmake-tools")
  if not ok or (type(qt.is_qmake_project) == "function" and not qt.is_qmake_project()) then
    return nil
  end
  local ok2, dir = pcall(function()
    local project = require("qmake-tools.project")
    local kits = require("qmake-tools.kits")
    local p = project.get(true)
    if not p then
      return nil
    end
    local kit = project.kit(project.config(p))
    return kit and kits.query(kit, "QT_INSTALL_DOCS")
  end)
  return ok2 and dir or nil
end

--- Projekt-Qt über cmake-tools.nvim (Qt6_DIR aus der CMakeCache.txt)
local function from_cmake_tools()
  local ok, cmake = pcall(require, "cmake-tools")
  if not ok or type(cmake.get_build_directory) ~= "function" then
    return nil
  end
  local ok2, bdir = pcall(cmake.get_build_directory)
  if not ok2 or not bdir then
    return nil
  end
  if type(bdir) == "table" then
    bdir = bdir.filename or tostring(bdir)
  end
  local cache = vim.fs.joinpath(bdir, "CMakeCache.txt")
  local fh = io.open(cache, "r")
  if not fh then
    return nil
  end
  local qt_dir
  for line in fh:lines() do
    local v = line:match("^Qt6_DIR:[%w]+=(.+)$") or line:match("^QT_DIR:[%w]+=(.+)$")
      or line:match("^Qt5_DIR:[%w]+=(.+)$") or line:match("^Qt6Core_DIR:[%w]+=(.+)$")
    if v and not v:match("NOTFOUND") then
      qt_dir = v
      break
    end
  end
  fh:close()
  if not qt_dir then
    return nil
  end
  -- <prefix>/lib/cmake/Qt6 → <prefix>/bin/qmake(6)
  local prefix = vim.fs.normalize(qt_dir):gsub("/lib/cmake/Qt%d?[%w]*$", "")
  for _, exe in ipairs({ "qmake6", "qmake", "qtpaths6", "qtpaths" }) do
    local p = vim.fs.joinpath(prefix, "bin", exe .. (is_win and ".exe" or ""))
    if uv.fs_stat(p) then
      local d = exe:match("qtpaths") and nil or qmake_docs(p)
      if d then
        return d
      end
    end
  end
  -- Online-Installer: <root>/<version>/<arch> → <root>/Docs/Qt-<version>
  local ver = version_of(prefix)
  if ver then
    local root = prefix:match("^(.*)/" .. vim.pesc(ver) .. "/")
    if root then
      return vim.fs.joinpath(root, "Docs", "Qt-" .. ver)
    end
  end
end

--- Kandidaten in typischen Installationsorten
local function system_candidates()
  local home = vim.fs.normalize("~")
  local res = {}
  local function glob(pattern)
    for _, p in ipairs(vim.fn.glob(pattern, true, true)) do
      res[#res + 1] = vim.fs.normalize(p)
    end
  end
  if vim.env.QT_DOC_DIR then
    res[#res + 1] = vim.env.QT_DOC_DIR
  end
  for _, exe in ipairs({ vim.env.QMAKE, "qmake6", "qmake", "qmake-qt5" }) do
    if exe and vim.fn.executable(exe) == 1 then
      local d = qmake_docs(vim.fn.exepath(exe))
      if d then
        res[#res + 1] = d
      end
    end
  end
  glob(home .. "/Qt/Docs/Qt-*")
  glob("/opt/Qt/Docs/Qt-*")
  glob("/opt/qt/Docs/Qt-*")
  if is_win then
    for _, drive in ipairs({ "C", "D", "E" }) do
      glob(drive .. ":/Qt/Docs/Qt-*")
    end
  end
  for _, p in ipairs({
    "/usr/share/qt6/doc", "/usr/share/doc/qt6", "/usr/share/qt5/doc", "/usr/share/doc/qt5",
    "/usr/share/doc/qt", "/usr/local/share/doc/qt6", "/opt/homebrew/share/qt/doc",
    "/usr/local/share/qt/doc", "/usr/local/opt/qt/doc", "/usr/lib/qt6/doc", "/usr/share/qt/doc",
  }) do
    res[#res + 1] = p
  end
  return res
end

--- Liste der zu indizierenden Pfade
---@return string[] paths, string|nil reason
function M.paths()
  local o = config.options
  if o.paths and #o.paths > 0 then
    local res = {}
    for _, p in ipairs(o.paths) do
      res[#res + 1] = vim.fs.normalize(vim.fn.expand(p))
    end
    return res, "Konfiguration"
  end
  local project = from_qmake_tools() or from_cmake_tools()
  local found, seen = {}, {}
  local function add(p, why)
    if p and not seen[p] and M.has_docs(p) then
      seen[p] = true
      found[#found + 1] = { path = p, why = why, version = version_of(p) }
    end
  end
  add(project, "Projekt-Kit")
  for _, p in ipairs(system_candidates()) do
    add(p, "System")
  end
  if #found == 0 then
    return {}, nil
  end
  if not o.single_version then
    return vim.tbl_map(function(f)
      return f.path
    end, found), "alle"
  end
  if found[1].why == "Projekt-Kit" then
    return { found[1].path }, "Projekt-Kit"
  end
  -- neueste Version, Verzeichnisse ohne Version (Distribution) zuletzt
  for i, f in ipairs(found) do
    f.order = i
  end
  table.sort(found, function(a, b)
    local va, vb = version_key(a.version), version_key(b.version)
    if va ~= vb then
      return va > vb
    end
    return a.order < b.order
  end)
  return { found[1].path }, "neueste Version"
end

return M
