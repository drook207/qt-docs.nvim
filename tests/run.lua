-- Headless-Tests:  nvim --headless -u NONE -l tests/run.lua
-- Optional mit echter Qt-Doku: QT_DOCS_TEST=/usr/share/qt6/doc nvim --headless -u NONE -l tests/run.lua
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(root)
vim.o.hidden = true
vim.o.swapfile = false
vim.cmd("runtime plugin/qt-docs.lua")

local T = { root = root }
local cases, failures = {}, 0

function T.case(name, fn)
  cases[#cases + 1] = { name = name, fn = fn }
end

function T.eq(a, b, msg)
  if not vim.deep_equal(a, b) then
    error((msg or "ungleich") .. "\nerwartet: " .. vim.inspect(b) .. "\nerhalten: " .. vim.inspect(a), 2)
  end
end

function T.ok(v, msg)
  if not v then
    error(msg or "Bedingung nicht erfüllt", 2)
  end
end

function T.wait(fn, ms)
  return vim.wait(ms or 5000, fn, 10)
end

function T.buf_text(buf)
  return table.concat(vim.api.nvim_buf_get_lines(buf or 0, 0, -1, false), "\n")
end

--- Fixture-Doku (eine .qch + ein HTML-Modul mit .index) bauen
function T.fixture()
  local dir = vim.fn.tempname()
  local res = vim.system({ "python3", "-I", root .. "/tests/fixtures/build_qch.py", dir }, { text = true }):wait()
  assert(res.code == 0, res.stderr)
  return dir
end

function T.setup(opts)
  local o = vim.tbl_deep_extend("force", { cache_dir = vim.fn.tempname(), window = "current" }, opts or {})
  require("qt-docs").setup(o)
  require("qt-docs.index").reset()
  require("qt-docs.viewer").clear_cache()
end

_G.T = T
for _, f in ipairs(vim.fn.globpath(root .. "/tests", "test_*.lua", false, true)) do
  dofile(f)
end

local only = os.getenv("TEST_FILTER")
local count = 0
for _, c in ipairs(cases) do
  if not only or c.name:find(only, 1, true) then
    count = count + 1
    vim.cmd("silent! only | silent! %bwipeout!")
    local ok, err = xpcall(c.fn, debug.traceback)
    if ok then
      print("ok    " .. c.name)
    else
      failures = failures + 1
      print("FAIL  " .. c.name .. "\n" .. tostring(err))
    end
  end
end
print(("%d Tests, %d Fehler"):format(count, failures))
os.exit(failures == 0 and 0 or 1)
