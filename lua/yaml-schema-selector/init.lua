-- yaml-schema-selector.nvim
--
-- Picks the JSON Schema for a YAML buffer with a Lua function, by acting as the
-- yaml-language-server's custom schema provider.

local config = require("yaml-schema-selector.config")
local discover = require("yaml-schema-selector.discover")
local lsp = require("yaml-schema-selector.lsp")
local registry = require("yaml-schema-selector.registry")
local selector = require("yaml-schema-selector.selector")

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

return M
