-- Edge cases / real Qt docs (QT_DOCS_TEST). Cases without QT_DOCS_TEST run with the fixture.
local T = _G.T
local real = os.getenv("QT_DOCS_TEST")
if real == "" then
  real = nil
end

local function wait_page(vpath, ms)
  return T.wait(function()
    return vim.b.qt_docs == vpath
  end, ms or 10000)
end

local function cursor_on(pattern)
  local lnum = vim.fn.search(pattern, "cw")
  T.ok(lnum > 0, "not found: " .. pattern)
  local s = vim.fn.match(vim.api.nvim_get_current_line(), pattern)
  vim.api.nvim_win_set_cursor(0, { lnum, s + 1 })
  return lnum
end

local function load_page(data, vpath)
  local page, err
  require("qt-docs.viewer").load(data, vpath, function(p, e)
    page, err = p, e
  end)
  T.wait(function()
    return page ~= nil or err ~= nil
  end, 10000)
  return page, err
end

local function capture_notify(fn)
  local msgs = {}
  local orig = vim.notify
  vim.notify = function(m, l)
    msgs[#msgs + 1] = { msg = m, level = l }
  end
  local ok, err = pcall(fn)
  vim.notify = orig
  return msgs, ok, err
end

-- ---------------------------------------------------------------------------
-- Robustness (fixture)
-- ---------------------------------------------------------------------------

T.case("edge: broken and empty .qch files in the docs folder are skipped", function()
  local dir = T.fixture()
  local fh = assert(io.open(dir .. "/broken.qch", "wb"))
  fh:write("this is not a sqlite file" .. string.rep("\0", 100))
  fh:close()
  assert(io.open(dir .. "/empty.qch", "wb")):close()
  T.setup({ paths = { dir } })
  local data, err = require("qt-docs.index").get_sync()
  T.ok(data, "no index: " .. tostring(err))
  T.eq(#data.sources, 2)
  T.eq(require("qt-docs.index").lookup(data, "QDemo::setName")[1].anchor, "setName")
end)

T.case("edge: nonexistent paths → no docs, no error", function()
  T.setup({ paths = { "/gibt/es/nicht", vim.fn.tempname() .. "/x.qch" }, online = { enabled = false } })
  local data, err
  local msgs, ok, perr = capture_notify(function()
    data, err = require("qt-docs.index").get_sync()
    vim.cmd("QtDoc QString")
  end)
  T.ok(ok, "error: " .. tostring(perr))
  T.eq(data, nil)
  T.ok(err, "no error message")
end)

T.case("edge: Python missing → message instead of Lua error (index)", function()
  local dir = T.fixture()
  T.setup({ paths = { dir }, python = "/nicht/vorhanden/python3" })
  local data, err = require("qt-docs.index").get_sync()
  T.eq(data, nil)
  T.ok(err and err:find("Python", 1, true), tostring(err))
end)

T.case("edge: Python missing, index from cache → :QtDoc raises no Lua error", function()
  local dir = T.fixture()
  local cache = vim.fn.tempname()
  T.setup({ paths = { dir }, cache_dir = cache })
  T.ok(require("qt-docs.index").get_sync(), "index")
  -- same cache, but Python is (no longer) available
  T.setup({ paths = { dir }, cache_dir = cache, python = "/nicht/vorhanden/python3" })
  local msgs, ok, err = capture_notify(function()
    vim.cmd("QtDoc QDemo::setName")
    vim.wait(500)
  end)
  T.ok(ok, "Lua error instead of message: " .. tostring(err))
end)

T.case("edge: cache directory cannot be created → index still usable or message", function()
  local dir = T.fixture()
  local file = vim.fn.tempname()
  vim.fn.writefile({ "x" }, file)
  -- parent path is a file → mkdir fails
  T.setup({ paths = { dir }, cache_dir = file .. "/cache" })
  local data, err
  local _, ok, perr = capture_notify(function()
    data, err = require("qt-docs.index").get_sync()
  end)
  T.ok(ok, "Lua error: " .. tostring(perr))
  T.ok(data or err, "neither index nor error message")
end)

T.case("edge: follow on a line without a link looks up the word", function()
  local dir = T.fixture()
  T.setup({ paths = { dir } })
  vim.cmd("QtDoc QDemo::setName")
  T.ok(wait_page("qtdemo/qdemo.html"), "page")
  -- heading "### void QDemo::setName(...)" has no link
  local line = vim.api.nvim_get_current_line()
  T.ok(not line:find("](", 1, true), line)
  local msgs, ok, err = capture_notify(function()
    vim.api.nvim_win_set_cursor(0, { vim.fn.line("."), 0 }) -- on "void"
    require("qt-docs.viewer").follow()
    vim.wait(300)
  end)
  T.ok(ok, tostring(err))
  T.eq(vim.b.qt_docs, "qtdemo/qdemo.html")
end)

-- ---------------------------------------------------------------------------
-- Real Qt docs
-- ---------------------------------------------------------------------------
if not real then
  return
end

local function setup_real(extra)
  T.setup(vim.tbl_deep_extend("force", { paths = { real }, online = { enabled = false } }, extra or {}))
  local data = require("qt-docs.index").get_sync()
  T.ok(data, "no index")
  return data
end

T.case("edge/real: typical keywords land at the right anchor", function()
  local data = setup_real()
  local index = require("qt-docs.index")
  local viewer = require("qt-docs.viewer")
  local expect = {
    { "QString::arg", "qtcore/qstring.html", "QString::arg(" },
    { "QObject::connect", "qtcore/qobject.html", "QObject::connect(" },
    { "QObject::tr", "qtcore/qobject.html", "QObject::tr(" },
    { "QList", "qtcore/qlist.html", "# QList Class" },
    { "QList::append", "qtcore/qlist.html", "QList::append(" },
    { "QMap::value", "qtcore/qmap.html", "QMap::value(" },
    { "Qt::AlignLeft", "qtcore/qt.html", "Qt::AlignmentFlag" },
    { "Qt::ConnectionType", "qtcore/qt.html", "enum Qt::ConnectionType" },
    { "QWidget::show", "qtwidgets/qwidget.html", "QWidget::show()" },
    { "QAbstractItemModel::data", "qtcore/qabstractitemmodel.html", "QAbstractItemModel::data(" },
    { "qDebug", "qtcore/qtglobal.html", "qDebug(" },
    { "Q_OBJECT", "qtcore/qobject.html", "### Q_OBJECT" },
    { "Q_PROPERTY", "qtcore/qobject.html", "### Q_PROPERTY" },
    { "QTimer::singleShot", "qtcore/qtimer.html", "QTimer::singleShot(" },
    { "QAbstractButton::clicked", "qtwidgets/qabstractbutton.html", "[signal] void QAbstractButton::clicked" },
    { "QWidget::enabled", "qtwidgets/qwidget.html", "### enabled : bool" },
    { "Signals & Slots", "qtcore/signalsandslots.html", "# Signals & Slots" },
  }
  local bad = {}
  for _, x in ipairs(expect) do
    local e = index.lookup(data, x[1])[1]
    if not e or e.vpath ~= x[2] then
      bad[#bad + 1] = x[1] .. " → " .. (e and e.vpath or "nothing")
    else
      local page = load_page(data, e.vpath)
      local sec = page and viewer.section(page, e.anchor) or {}
      if not (sec[1] or ""):find(x[3], 1, true) then
        bad[#bad + 1] = x[1] .. " → " .. tostring(sec[1])
      end
    end
  end
  T.eq(bad, {})
end)

T.case("edge/real: inherited members (QPushButton::setText, QFile::readAll)", function()
  local data = setup_real()
  local index = require("qt-docs.index")
  local miss = {}
  for _, k in ipairs({ "QPushButton::setText", "QPushButton::clicked", "QFile::readAll", "QStringList::append",
    "QMainWindow::show" }) do
    if #index.lookup(data, k) == 0 then
      miss[#miss + 1] = k
    end
  end
  T.eq(miss, {})
end)

T.case("edge/real: constructor, QIODevice::ReadOnly, fully qualified enum value, template argument", function()
  local data = setup_real()
  local index = require("qt-docs.index")
  local miss = {}
  for _, k in ipairs({ "QWidget::QWidget", "QString::QString", "QIODevice::ReadOnly",
    "Qt::AlignmentFlag::AlignLeft", "QList<int>" }) do
    if #index.lookup(data, k) == 0 then
      miss[#miss + 1] = k
    end
  end
  T.eq(miss, {})
end)

T.case("edge/real: link to another module, overload anchor, history", function()
  setup_real()
  local viewer = require("qt-docs.viewer")
  vim.cmd("QtDoc QWidget")
  T.ok(wait_page("qtwidgets/qwidget.html"), "QWidget")
  local win = vim.api.nvim_get_current_win()
  cursor_on("\\[QObject\\](qtcore/qobject.html)")
  viewer.follow()
  T.ok(wait_page("qtcore/qobject.html"), "QObject across module boundary")
  T.eq(vim.api.nvim_get_current_win(), win)
  -- overload: link to connect-1 (second connect overload)
  vim.cmd("normal! gg")
  cursor_on("\\[connect\\](#connect-1)")
  viewer.follow()
  T.ok(T.wait(function()
    return vim.api.nvim_get_current_line():match("^### .*QObject::connect%(const QObject %*sender, const QMetaMethod")
  end), "wrong overload: " .. vim.api.nvim_get_current_line())
  viewer.history_move(-1)
  T.ok(T.wait(function()
    return vim.b.qt_docs == "qtcore/qobject.html" and not vim.api.nvim_get_current_line():match("^### ")
  end), "back (same page)")
  viewer.history_move(-1)
  T.ok(wait_page("qtwidgets/qwidget.html"), "back to QWidget")
  viewer.history_move(1)
  T.ok(wait_page("qtcore/qobject.html"), "forward")
end)

T.case("edge/real: many pages → one docs window, buffers are reused", function()
  setup_real({ window = "vsplit" })
  local wins0 = #vim.api.nvim_tabpage_list_wins(0)
  local kws = { "QString", "QObject", "QWidget", "QList", "QMap", "QTimer", "QString", "QObject" }
  for _, k in ipairs(kws) do
    vim.cmd("QtDoc " .. k)
    T.ok(T.wait(function()
      return (vim.b.qt_docs or ""):find(k:lower() .. ".html", 1, true) ~= nil
    end, 10000), "not opened: " .. k)
  end
  T.eq(#vim.api.nvim_tabpage_list_wins(0), wins0 + 1, "multiple docs windows")
  local n = 0
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_get_name(b):match("^qtdoc://") then
      n = n + 1
    end
  end
  T.eq(n, 6)
end)

T.case("edge/real: window=float opens a float and follows links inside it", function()
  setup_real({ window = "float" })
  vim.cmd("QtDoc QTimer")
  T.ok(wait_page("qtcore/qtimer.html"), "QTimer")
  local win = vim.api.nvim_get_current_win()
  T.ok(vim.api.nvim_win_get_config(win).relative ~= "", "no float")
  cursor_on("\\[QObject\\](qtcore/qobject.html)")
  require("qt-docs.viewer").follow()
  T.ok(wait_page("qtcore/qobject.html"), "link in the float")
  T.eq(vim.api.nvim_get_current_win(), win)
  vim.cmd("QtDoc QString")
  T.ok(wait_page("qtcore/qstring.html"), "second page")
  local floats = 0
  for _, w in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_config(w).relative ~= "" then
      floats = floats + 1
    end
  end
  T.eq(floats, 1)
end)

T.case("edge/real: :QtDocSearch with prefix", function()
  setup_real()
  local items
  local orig = vim.ui.select
  vim.ui.select = function(it, _, cb)
    items = it
  end
  local ok, err = pcall(vim.cmd, "QtDocSearch QString::ar")
  vim.ui.select = orig
  assert(ok, err)
  T.ok(T.wait(function()
    return items ~= nil
  end), "no picker")
  T.ok(vim.tbl_contains(items, "QString::arg"), vim.inspect(items))
  for _, it in ipairs(items) do
    T.ok(it:lower():sub(1, 10) == "qstring::a", it)
  end
end)

T.case("edge/real: hover section class and property", function()
  local data = setup_real()
  local viewer = require("qt-docs.viewer")
  local page = load_page(data, "qtwidgets/qwidget.html")
  local sec = viewer.section(page, "enabled-prop")
  T.eq(sec[1], "### enabled : bool")
  T.ok(#sec < 40, "section too long: " .. #sec)
  local top = viewer.section(page, "")
  T.eq(top[1], "# QWidget Class")
  T.ok(#top < 30, "class hover too long: " .. #top)
end)

T.case("edge/real: rendering – property list is not a single code line", function()
  local data = setup_real()
  local page = load_page(data, "qtwidgets/qwidget.html")
  local bad = {}
  for _, l in ipairs(page.lines) do
    if l:match("^%s*%- `[^`]*%*%*%[") or #l > 2000 then
      bad[#bad + 1] = l:sub(1, 120) .. " … (" .. #l .. " characters)"
    end
  end
  T.eq(bad, {})
  T.ok(page.anchors["acceptDrops-prop"], "anchor")
  local found = false
  for _, l in ipairs(page.lines) do
    if l:find("[acceptDrops](#acceptDrops-prop)", 1, true) and #l < 200 then
      found = true
    end
  end
  T.ok(found, "property acceptDrops not on its own line")
end)

T.case("edge/real: rendering – members page as a list", function()
  local data = setup_real()
  local page = load_page(data, "qtcore/qstring-members.html")
  local long = 0
  for _, l in ipairs(page.lines) do
    if #l > 1000 then
      long = long + 1
    end
  end
  T.eq(long, 0, "members page has huge lines")
end)

T.case("edge/real: hover over an overload shows all/matching overloads", function()
  local data = setup_real()
  local viewer = require("qt-docs.viewer")
  local page = load_page(data, "qtcore/qstring.html")
  local sec = table.concat(viewer.section(page, "arg"), "\n")
  -- QString::arg has >10 overloads (arg-1 …); the hover shows only the first
  T.ok(sec:find("QString::arg(int a", 1, true) or sec:find("QString::arg(qlonglong", 1, true),
    "only the first overload in the hover:\n" .. sec:sub(1, 200))
end)

T.case("edge/real: anchor missing on the page → fallback hits the wrong heading", function()
  local data = setup_real()
  local index = require("qt-docs.index")
  local viewer = require("qt-docs.viewer")
  -- index: QString::iterator → #iterator-typedef, page only has #iterator-typedefx
  local e = index.lookup(data, "QString::iterator")[1]
  local page = load_page(data, e.vpath)
  T.eq(viewer.section(page, e.anchor)[1], "### QString::iterator")
end)
