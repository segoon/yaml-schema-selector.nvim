-- yaml-schema-selector.nvim
--
-- Picks the JSON Schema for a YAML buffer with a Lua function, by acting as the
-- yaml-language-server's custom schema provider.

local config = require("yaml-schema-selector.config")
local discover = require("yaml-schema-selector.discover")
local lsp = require("yaml-schema-selector.lsp")
local registry = require("yaml-schema-selector.registry")
local selector = require("yaml-schema-selector.selector")
local status_cache = require("yaml-schema-selector.status_cache")

local M = {}

---@type yss.Config|nil
M.config = nil

---Configure the plugin and layer onto the language server.
---@param opts table|nil See |yaml-schema-selector-config|.
function M.setup(opts)
  M.config = config.build(opts)
  if M.config.discover then
    discover.discover()
  end
  selector.reset()
  status_cache.reset()
  lsp.setup(M.config)
end

---Register a schema selector, a set of schema aliases, or both.
---Safe to call at any time, independent of `setup()` -- other plugins can
---call this from their own `setup()`/init, regardless of load order.
---@param spec yss.Registration
function M.register(spec)
  registry.register(spec)
end

---Remove a previously registered entry, if any. A no-op otherwise.
---@param name string
function M.unregister(name)
  registry.unregister(name)
end

---Re-scan 'runtimepath' for lua/yaml-schema-selector/schemas/**/*.lua files
---and (re-)register what they return. Called automatically by `setup()` when
---`opts.discover` is true (the default); exposed here for manual reload
---(e.g. from `:so %` during development) regardless of that flag.
function M.discover()
  discover.discover()
end

---@return yss.Config
local function require_config()
  if not M.config then
    error("yaml-schema-selector: setup() has not been called", 0)
  end
  return M.config
end

---Force the language server to re-resolve the schema of every open document.
---Call this when something the selector depends on changed outside of Neovim.
function M.refresh()
  local cfg = require_config()
  -- Give registered selectors a chance to invalidate state a buffer
  -- changedtick can't reach on its own (e.g. schemas generated from files
  -- other than the buffer itself).
  registry.refresh()
  for _, client in ipairs(lsp.clients(cfg)) do
    lsp.revalidate(client)
  end
end

---Run the selector for a buffer and return the schema that would be sent.
---Returns `nil` when no schema would be chosen. Debugging aid; also used by
---|:checkhealth|.
---@param bufnr integer|nil Defaults to the current buffer.
---@return string|string[]|nil
function M.resolve(bufnr)
  local cfg = require_config()
  bufnr = (bufnr == nil or bufnr == 0) and vim.api.nvim_get_current_buf() or bufnr

  local client = lsp.clients(cfg)[1]
  if not client then
    return nil
  end

  local result = selector.resolve(cfg, vim.uri_from_bufnr(bufnr), client)
  if result == vim.NIL then
    return nil
  end
  return result
end

---@class yss.Status
---@field schema string|string[]|nil The resolved schema, or nil if nothing matched.
---@field source string|nil Name of the registration that answered, or nil.
---@field uri string Document URI.
---@field path string Absolute filesystem path of the document.

---Like `resolve()`, but also reports which registration answered. Runs the
---full selector chain every call (including `ctx.yaml()` parsing) -- a
---debugging aid, not something to call on every redraw. For that, see
---`statusline()`.
---@param bufnr integer|nil Defaults to the current buffer.
---@return yss.Status
function M.status(bufnr)
  local cfg = require_config()
  bufnr = (bufnr == nil or bufnr == 0) and vim.api.nvim_get_current_buf() or bufnr
  local uri = vim.uri_from_bufnr(bufnr)

  local client = lsp.clients(cfg)[1]
  if not client then
    return { schema = nil, source = nil, uri = uri, path = vim.uri_to_fname(uri) }
  end

  local detailed = selector.resolve_detailed(cfg, uri, client)
  local schema = nil
  if detailed.schema ~= vim.NIL then
    schema = detailed.schema
  end
  return {
    schema = schema,
    source = detailed.source,
    uri = uri,
    path = vim.uri_to_fname(uri),
  }
end

---@class yss.RegistrationInfo
---@field name string
---@field priority integer
---@field kind "select"|"matcher"
---@field discovered boolean Whether this entry came from autodiscovery.

---Currently registered selectors, sorted by priority (highest first). A
---read-only summary for introspection (statuslines, pickers, etc.) -- does
---not expose the underlying functions. See also `:checkhealth`.
---@return yss.RegistrationInfo[]
function M.registrations()
  local discovered = discover.discovered()
  local out = {}
  for _, entry in ipairs(registry.sorted()) do
    out[#out + 1] = {
      name = entry.name,
      priority = entry.priority or 50,
      kind = entry.select and "select" or "matcher",
      discovered = discovered[entry.name] == true,
    }
  end
  return out
end

---The merged schema alias table: `setup()`'s `schemas` plus every
---registration's `schemas`, `setup()`'s values winning on conflict.
---@return table<string, string>
function M.schemas()
  return selector.merged_schemas(require_config())
end

---@class yss.StatuslineInfo
---@field schema string|string[]|nil
---@field source string|nil
---@field label string Short display label: alias name, else basename, else the raw schema.

---Cheap, cache-only view of the last resolution for a buffer -- safe to call
---from a statusline redraw, unlike `status()`/`resolve()`. Returns nil until
---the server has actually asked for (and gotten an answer to) this buffer's
---schema at least once.
---@param bufnr integer|nil Defaults to the current buffer.
---@return yss.StatuslineInfo|nil
function M.statusline(bufnr)
  bufnr = (bufnr == nil or bufnr == 0) and vim.api.nvim_get_current_buf() or bufnr
  local entry = status_cache.get(bufnr)
  if not entry then
    return nil
  end

  local label
  if type(entry.schema) == "string" then
    local schemas = M.config and selector.merged_schemas(M.config) or {}
    for alias, value in pairs(schemas) do
      if value == entry.schema then
        label = alias
        break
      end
    end
    label = label or vim.fs.basename(entry.schema)
  elseif type(entry.schema) == "table" then
    label = tostring(#entry.schema) .. " schemas"
  else
    label = ""
  end

  return { schema = entry.schema, source = entry.source, label = label }
end

return M
