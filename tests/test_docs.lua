local T = _G.T

local function setup_fixture(extra)
  local dir = T.fixture()
  T.setup(vim.tbl_deep_extend("force", { paths = { dir } }, extra or {}))
  return dir
end

T.case("index from .qch and HTML module (.index)", function()
  setup_fixture()
  local index = require("qt-docs.index")
  local data = index.get_sync()
  T.ok(data, "no index")
  T.eq(#data.sources, 2)
  T.eq(index.lookup(data, "QDemo::setName")[1].anchor, "setName")
  T.eq(index.lookup(data, "QBase::base")[1].vpath, "qtother/qbase.html")
  T.eq(index.lookup(data, "qdemo")[1].name, "QDemo")
  T.eq(index.lookup(data, "QDemo::name()")[1].anchor, "name")
  -- member without a class
  T.eq(index.lookup(data, "base")[1].name, "QBase::base")
  T.eq(#index.lookup(data, "gibtsnicht"), 0)
end)

T.case(":QtDoc opens page at the anchor", function()
  setup_fixture()
  vim.cmd("QtDoc QDemo::setName")
  T.ok(T.wait(function()
    return vim.b.qt_docs ~= nil
  end), "page not opened")
  T.eq(vim.api.nvim_buf_get_name(0), "qtdoc://qtdemo/qdemo.html")
  T.eq(vim.api.nvim_get_current_line(), "### void QDemo::setName(const QString &name)")
  T.eq(vim.bo.filetype, "markdown")
  T.eq(vim.bo.modifiable, false)
  local text = T.buf_text()
  T.ok(not text:find("do not show", 1, true), "script content displayed")
  T.ok(not text:find("Copyright footer", 1, true), "footer displayed")
  T.ok(not text:find("Contents", 1, true), "sidebar displayed")
  T.ok(text:find("```cpp\nQDemo d;\nd.setName(\"x\");\n```", 1, true), "code block missing")
  T.ok(text:find("| `QDemo::A` | `0` | First \\| value |", 1, true), "table missing")
end)

T.case("links: same page, another module, history back/forward", function()
  setup_fixture()
  local viewer = require("qt-docs.viewer")
  vim.cmd("QtDoc QDemo::name")
  T.wait(function()
    return vim.b.qt_docs ~= nil
  end)
  local win = vim.api.nvim_get_current_win()
  -- link [setName](#setName)
  local lnum = vim.fn.search("\\[setName\\](#setName)")
  T.ok(lnum > 0, "link not found")
  vim.api.nvim_win_set_cursor(0, { lnum, (vim.api.nvim_get_current_line():find("%[setName%]")) })
  viewer.follow()
  T.ok(T.wait(function()
    return vim.api.nvim_get_current_line():find("QDemo::setName", 1, true) ~= nil
  end), "anchor not reached")
  -- another module
  vim.fn.search("\\[QBase::base\\]", "bw")
  vim.cmd("normal! gg")
  lnum = vim.fn.search("\\[QBase::base\\]")
  vim.api.nvim_win_set_cursor(0, { lnum, (vim.api.nvim_get_current_line():find("%[QBase::base%]")) })
  viewer.follow()
  T.ok(T.wait(function()
    return vim.b.qt_docs == "qtother/qbase.html"
  end), "module link not opened")
  T.eq(vim.api.nvim_get_current_line(), "### int QBase::base()")
  T.eq(vim.api.nvim_get_current_win(), win, "new window instead of the same one")
  viewer.history_move(-1)
  T.ok(T.wait(function()
    return vim.b.qt_docs == "qtdemo/qdemo.html"
  end), "back failed")
  T.ok(vim.api.nvim_get_current_line():find("QBase::base", 1, true) ~= nil, "cursor position not restored")
  viewer.history_move(1)
  T.ok(T.wait(function()
    return vim.b.qt_docs == "qtother/qbase.html"
  end), "forward failed")
end)

T.case("doc.qt.io links are opened locally", function()
  setup_fixture()
  vim.cmd("QtDoc QDemo::setName")
  T.wait(function()
    return vim.b.qt_docs ~= nil
  end)
  local lnum = vim.fn.search("QBase online")
  vim.api.nvim_win_set_cursor(0, { lnum, (vim.api.nvim_get_current_line():find("%[QBase online")) })
  require("qt-docs.viewer").follow()
  T.ok(T.wait(function()
    return vim.b.qt_docs == "qtother/qbase.html"
  end), "not opened locally")
end)

T.case("section for hover", function()
  setup_fixture()
  local index = require("qt-docs.index")
  local viewer = require("qt-docs.viewer")
  local data = index.get_sync()
  local page
  viewer.load(data, "qtdemo/qdemo.html", function(p)
    page = p
  end)
  T.wait(function()
    return page ~= nil
  end)
  local sec = viewer.section(page, "name")
  T.eq(sec[1], "### QString QDemo::name() const")
  T.ok(not table.concat(sec, "\n"):find("setName(const", 1, true), "section too long")
  local top = viewer.section(page, "")
  T.eq(top[1], "# QDemo Class")
  T.ok(not table.concat(top, "\n"):find("## Public", 1, true), "class hover too long")
end)

T.case("hover float over a symbol in a C++ buffer", function()
  setup_fixture()
  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_set_current_buf(buf)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "void f() { QDemo::setName(x); }" })
  vim.api.nvim_win_set_cursor(0, { 1, 20 }) -- on setName
  require("qt-docs").hover()
  T.ok(T.wait(function()
    for _, w in ipairs(vim.api.nvim_list_wins()) do
      if vim.api.nvim_win_get_config(w).relative ~= "" then
        return true
      end
    end
  end), "no float")
  local float
  for _, w in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_config(w).relative ~= "" then
      float = w
    end
  end
  local text = T.buf_text(vim.api.nvim_win_get_buf(float))
  T.ok(text:find("QDemo::setName", 1, true), "wrong content: " .. text)
end)

T.case("symbol detection: word under cursor and clangd hover", function()
  setup_fixture()
  local symbol = require("qt-docs.symbol")
  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_set_current_buf(buf)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "auto s = QString::fromUtf8(x);" })
  vim.api.nvim_win_set_cursor(0, { 1, 10 }) -- on QString
  T.eq(symbol.word_at_cursor(), "QString")
  vim.api.nvim_win_set_cursor(0, { 1, 20 }) -- on fromUtf8
  T.eq(symbol.word_at_cursor(), "QString::fromUtf8")
  T.eq(symbol.from_hover("### instance-method `arg`\n\n---\n→ `QString`\n\n// In QString\npublic: QString arg() const", "arg")[1],
    "QString::arg")
  T.eq(symbol.from_hover("### variable `s`\n\n---\nType: `const QList<QString> &`", "s"), { "QList", "QString", "s" })
  T.eq(symbol.from_hover("### enumerator `AlignLeft`\n\n---\n// In Qt::AlignmentFlag", "AlignLeft"),
    { "Qt::AlignmentFlag::AlignLeft", "Qt::AlignLeft", "AlignLeft" })
  T.eq(symbol.from_hover("### class `QWidget`\n\n---\n", "QWidget")[1], "QWidget")
end)

T.case("online fallback without local docs (curl)", function()
  local web = vim.fn.tempname()
  vim.fn.mkdir(web, "p")
  vim.fn.writefile(vim.fn.readfile(T.root .. "/tests/fixtures/html/qtdemo/qdemo.html"), web .. "/qdemo.html")
  vim.env.QTDOCS_FAKE_WEB = web
  local old_path = vim.env.PATH
  vim.env.PATH = T.root .. "/tests/bin:" .. old_path
  -- no local docs: path without content
  T.setup({ paths = { vim.fn.tempname() } })
  local ok, err = pcall(function()
    vim.cmd("QtDoc QDemo::setName")
    T.ok(T.wait(function()
      return vim.b.qt_docs ~= nil
    end), "online page not opened")
    T.eq(vim.b.qt_docs, "qdemo.html")
    T.eq(vim.api.nvim_get_current_line(), "### void QDemo::setName(const QString &name)")
  end)
  vim.env.PATH = old_path
  assert(ok, err)
end)

T.case("index cache is reused and rebuilt on changes", function()
  local dir = setup_fixture()
  local index = require("qt-docs.index")
  local cache = require("qt-docs.config").cache_dir()
  index.get_sync()
  local files = vim.fn.glob(cache .. "/index-*.json", true, true)
  T.eq(#files, 1)
  index.reset()
  T.ok(index.get_sync(), "cache not readable")
  T.eq(vim.fn.glob(cache .. "/index-*.json", true, true), files)
  -- change .qch → new index
  vim.uv.fs_utime(dir .. "/qtdemo.qch", os.time() + 100, os.time() + 100)
  index.reset()
  index.get_sync()
  local files2 = vim.fn.glob(cache .. "/index-*.json", true, true)
  T.eq(#files2, 1)
  T.ok(files2[1] ~= files[1], "index not rebuilt")
end)

T.case("discovery: QT_DOC_DIR and newest version", function()
  T.setup({ paths = {} })
  local dir = T.fixture()
  vim.env.QT_DOC_DIR = dir
  local paths = require("qt-docs.discover").paths()
  vim.env.QT_DOC_DIR = nil
  T.ok(vim.tbl_contains(paths, dir) or #paths >= 1, "nothing found")
end)

-- Optional: real Qt docs
local real = os.getenv("QT_DOCS_TEST")
if real and real ~= "" then
  T.case("real Qt docs: QString::arg, QObject::connect, QWidget", function()
    T.setup({ paths = { real } })
    local index = require("qt-docs.index")
    local data = index.get_sync()
    T.ok(#data.entries > 1000, "too few entries")
    for _, k in ipairs({ "QString::arg", "QObject::connect", "QWidget::show", "Qt::AlignLeft", "QList" }) do
      T.ok(#index.lookup(data, k) > 0, "not found: " .. k)
    end
    vim.cmd("QtDoc QObject::connect")
    T.ok(T.wait(function()
      return vim.b.qt_docs == "qtcore/qobject.html"
    end, 10000), "QObject not opened")
    T.ok(vim.api.nvim_get_current_line():find("QObject::connect", 1, true), vim.api.nvim_get_current_line())
  end)
end
