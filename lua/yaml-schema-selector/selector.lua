-- Builds the context handed to the user's `select` function and turns its
-- answer into a `custom/schema/request` response.

local aliases = require("yaml-schema-selector.aliases")
local yaml = require("yaml-schema-selector.yaml")

local M = {}

---Error messages already reported, so a broken selector cannot spam the user
---on every keystroke.
---@type table<string, true>
local reported = {}

---Cache of parsed documents, keyed by buffer and invalidated by changedtick.
---@type table<integer, { tick: integer, documents: table[] }>
local parse_cache = {}

---Report an error at most once per distinct message.
---@param message string
local function notify_once(message)
  if reported[message] then
    return
  end
  reported[message] = true
  vim.notify("yaml-schema-selector: " .. message, vim.log.levels.ERROR)
end

---Forget which errors have been reported. Used by tests and `setup()`.
function M.reset()
  reported = {}
  parse_cache = {}
end

---The server sends the document URI as a by-position parameter, so it arrives
---as a one-element list; older/other transports may send a bare string.
---@param params any
---@return string|nil
function M.params_to_uri(params)
  if type(params) == "string" then
    return params
  end
  if type(params) == "table" and type(params[1]) == "string" then
    return params[1]
  end
  return nil
end

---Read the document's text, preferring the loaded buffer over the file on disk.
---@param bufnr integer|nil
---@param path string
---@return string|nil
local function read_source(bufnr, path)
  if bufnr and vim.api.nvim_buf_is_loaded(bufnr) then
    return table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n")
  end
  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok then
    return nil
  end
  return table.concat(lines, "\n")
end

---Parse the document, memoized per buffer for as long as it stays unchanged.
---@param cfg yss.Config
---@param bufnr integer|nil
---@param path string
---@return table[]
local function parse_documents(cfg, bufnr, path)
  local tick = bufnr and vim.api.nvim_buf_is_valid(bufnr) and vim.api.nvim_buf_get_changedtick(bufnr) or nil
  local cached = bufnr and parse_cache[bufnr]
  if cached and tick and cached.tick == tick then
    return cached.documents
  end

  local source = read_source(bufnr, path)
  if not source then
    return {}
  end
  if #source > cfg.max_parse_bytes then
    notify_once(("%s is larger than max_parse_bytes (%d), ctx.yaml() is unavailable"):format(path, cfg.max_parse_bytes))
    return {}
  end

  local ok, documents = pcall(yaml.parse, source)
  if not ok then
    notify_once("failed to parse YAML: " .. tostring(documents))
    return {}
  end

  if bufnr and tick then
    parse_cache[bufnr] = { tick = tick, documents = documents }
  end
  return documents
end

---Find the buffer holding a path, without creating one.
---`vim.fn.bufnr()` matches by pattern and `vim.uri_to_bufnr()` creates a buffer,
---so neither is usable here.
---@param path string
---@return integer|nil
local function find_buf(path)
  local target = vim.fs.normalize(path)
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.fs.normalize(vim.api.nvim_buf_get_name(bufnr)) == target then
      return bufnr
    end
  end
  return nil
end

---Assemble the context table for a document.
---@param cfg yss.Config
---@param uri string
---@param client vim.lsp.Client
---@return yss.Context
function M.build_context(cfg, uri, client)
  local path = vim.uri_to_fname(uri)
  local bufnr = find_buf(path)

  local documents ---@type table[]|nil
  local function all_documents()
    if not documents then
      documents = parse_documents(cfg, bufnr, path)
    end
    return documents
  end

  return {
    uri = uri,
    path = path,
    filename = vim.fs.basename(path),
    bufnr = bufnr,
    filetype = bufnr and vim.bo[bufnr].filetype or nil,
    root_dir = client.root_dir,
    client_id = client.id,
    schemas = cfg.schemas,
    lines = function(n)
      local source = read_source(bufnr, path) or ""
      local lines = vim.split(source, "\n")
      if n and n < #lines then
        return vim.list_slice(lines, 1, n)
      end
      return lines
    end,
    yaml = function()
      return all_documents()[1]
    end,
    yaml_documents = all_documents,
  }
end

---Run the user's selector for a document and normalize its answer.
---Always returns something sendable: `vim.NIL` means "no opinion, fall back".
---@param cfg yss.Config
---@param uri string
---@param client vim.lsp.Client
---@return string|string[]|vim.NIL
function M.resolve(cfg, uri, client)
  local ctx = M.build_context(cfg, uri, client)

  local ok, selection = pcall(cfg.select, ctx)
  if not ok then
    notify_once("select() failed for " .. ctx.path .. ": " .. tostring(selection))
    return vim.NIL
  end

  local base_dir = client.root_dir or vim.fs.dirname(ctx.path)
  local normalized_ok, normalized = pcall(aliases.normalize, selection, cfg.schemas, base_dir)
  if not normalized_ok then
    notify_once("could not resolve the schema returned for " .. ctx.path .. ": " .. tostring(normalized))
    return vim.NIL
  end

  return normalized
end

return M
