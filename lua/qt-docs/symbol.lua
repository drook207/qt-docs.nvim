-- Translate the symbol under the cursor into doc keywords.
-- With clangd: evaluate the hover (method → Class::method, variable → its type).
local config = require("qt-docs.config")

local M = {}

--- Identifier (with ::) under the cursor
function M.word_at_cursor()
  local line = vim.api.nvim_get_current_line()
  local col = vim.api.nvim_win_get_cursor(0)[2] + 1
  local s, e = col, col
  local function ok(ch)
    return ch ~= "" and ch:match("[%w_:~]") ~= nil
  end
  if not ok(line:sub(col, col)) then
    return vim.fn.expand("<cword>")
  end
  while s > 1 and ok(line:sub(s - 1, s - 1)) do
    s = s - 1
  end
  while e < #line and ok(line:sub(e + 1, e + 1)) do
    e = e + 1
  end
  local w = line:sub(s, e):gsub("^:+", ""):gsub(":+$", "")
  -- only up to the part under the cursor: QString::fromUtf8 with cursor on QString → QString
  local rel = col - s + 1
  local upto = w:find("::", rel, true)
  if upto then
    w = w:sub(1, upto - 1)
  end
  return w
end

--- Clean up the type: "const QList<QString> &" → "QList", template arguments separately
local function clean_type(t)
  t = t:gsub("%f[%w_]const%f[^%w_]", ""):gsub("%f[%w_]volatile%f[^%w_]", "")
  t = t:gsub("[%*&]", "")
  local outer = t:gsub("<.*>", "")
  local inner = t:match("<%s*([%w_:]+)")
  return vim.trim(outer), inner
end

--- Candidates from a clangd hover text
function M.from_hover(text, word)
  local cands = {}
  local function add(c)
    if c and c ~= "" and not vim.tbl_contains(cands, c) then
      cands[#cands + 1] = c
    end
  end
  local kind, name = text:match("###%s+([%w%-]+)%s+`([^`]+)`")
  name = name or word
  local scope = text:match("//%s*In%s+([%w_:]+)")
  local ns = text:match("//%s*In%s+namespace%s+([%w_:]+)")
  scope = (scope ~= "namespace") and scope or ns
  local typ = text:match("Type:%s*`([^`]+)`")
  if kind == "variable" or kind == "param" or kind == "field" or kind == "local" then
    if typ then
      local outer, inner = clean_type(typ)
      add(outer)
      add(inner)
    end
    if scope and kind == "field" then
      add(scope .. "::" .. name)
    end
  elseif kind == "enumerator" and scope then
    add(scope .. "::" .. name)
    -- unscoped enum: Qt::AlignmentFlag::AlignLeft → Qt::AlignLeft
    local outer = scope:match("^(.*)::[%w_]+$")
    if outer then
      add(outer .. "::" .. name)
    end
  elseif scope then
    add(scope .. "::" .. name)
  end
  add(name)
  if typ and kind ~= "variable" then
    add((clean_type(typ)))
  end
  return cands
end

local function clangd_hover(buf)
  if not config.options.use_clangd then
    return nil
  end
  local get = vim.lsp.get_clients or vim.lsp.get_active_clients
  for _, c in ipairs(get({ bufnr = buf, name = "clangd" })) do
    local params = vim.lsp.util.make_position_params(0, c.offset_encoding or "utf-16")
    local ok, resp = pcall(function()
      if vim.fn.has("nvim-0.11") == 1 then
        return c:request_sync("textDocument/hover", params, 1500, buf)
      end
      return c.request_sync("textDocument/hover", params, 1500, buf)
    end)
    if ok and resp and resp.result and resp.result.contents then
      local contents = resp.result.contents
      if type(contents) == "table" then
        contents = contents.value or table.concat(vim.tbl_map(function(x)
          return type(x) == "table" and x.value or tostring(x)
        end, contents), "\n")
      end
      return contents
    end
  end
end

--- Candidates for the symbol under the cursor (best first)
function M.candidates(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  local word = M.word_at_cursor()
  local cands = {}
  local hover = clangd_hover(buf)
  if hover then
    cands = M.from_hover(hover, word)
  end
  if word and word ~= "" and not vim.tbl_contains(cands, word) then
    cands[#cands + 1] = word
  end
  return cands, word
end

return M
