-- `:checkhealth yaml-schema-selector`

local M = {}

---@param cfg yss.Config
local function check_treesitter(cfg)
  local _ = cfg
  local ok = pcall(vim.treesitter.get_string_parser, "a: b", "yaml")
  if ok then
    vim.health.ok("`yaml` treesitter parser is available")
  else
    vim.health.warn(
      "`yaml` treesitter parser is missing",
      { "Install it (e.g. `:TSInstall yaml`); without it `ctx.yaml()` always returns nil" }
    )
  end
end

---@param cfg yss.Config
local function check_server(cfg)
  if vim.fn.executable("yaml-language-server") == 1 then
    vim.health.ok("`yaml-language-server` found in $PATH")
  else
    vim.health.warn("`yaml-language-server` not found in $PATH", {
      "Install it with `npm install -g yaml-language-server`,",
      "or make sure your LSP config points at another location.",
    })
  end

  local lsp = require("yaml-schema-selector.lsp")
  local clients = lsp.clients(cfg)
  if #clients == 0 then
    vim.health.warn(("no running LSP client named `%s`"):format(cfg.server_name), {
      "This plugin never starts the server; configure and enable it yourself,",
      "e.g. `vim.lsp.enable('yamlls')`.",
    })
    return
  end

  for _, client in ipairs(clients) do
    if client.handlers and client.handlers[lsp.SCHEMA_REQUEST] then
      vim.health.ok(("client %d (%s): schema provider installed"):format(client.id, client.name))
    else
      vim.health.error(("client %d (%s): schema provider is NOT installed"):format(client.id, client.name))
    end
  end
end

local function check_current_buffer()
  local ok, result = pcall(require("yaml-schema-selector").resolve, 0)
  if not ok then
    vim.health.error("failed to resolve a schema for the current buffer: " .. tostring(result))
  elseif result == nil then
    vim.health.info("resolved schema for current buffer: none (the server falls back to its own resolution)")
  else
    vim.health.info("resolved schema for current buffer: " .. vim.inspect(result))
  end
end

---@param cfg yss.Config
local function check_registry(cfg)
  local registry = require("yaml-schema-selector.registry")
  local discover = require("yaml-schema-selector.discover")
  local sorted = registry.sorted()
  local registered_schemas = registry.schemas()
  local discovered = discover.discovered()

  if #sorted == 0 and vim.tbl_isempty(registered_schemas) and vim.tbl_isempty(cfg.schemas) then
    vim.health.warn(
      "no selectors and no schema aliases configured anywhere",
      { "Nothing can ever answer a schema request; call `register()` or set `schemas` in `setup()`." }
    )
    return
  end

  if #sorted == 0 then
    vim.health.info("no selectors registered via `register()`")
  else
    local via_discovery = 0
    for _, entry in ipairs(sorted) do
      local tag = discovered[entry.name] and " [discovered]" or ""
      if discovered[entry.name] then
        via_discovery = via_discovery + 1
      end
      local kind = entry.select and "select" or "matcher+schema"
      vim.health.info(
        ("registered selector %q (priority %d, %s)%s"):format(entry.name, entry.priority or 50, kind, tag)
      )
    end
    vim.health.ok(("%d selector(s) registered (%d via autodiscovery)"):format(#sorted, via_discovery))
  end

  vim.health.info(("%d schema alias(es) contributed via `register()`"):format(vim.tbl_count(registered_schemas)))

  local discover_errors = discover.errors()
  if #discover_errors > 0 then
    local lines = vim.tbl_map(function(e)
      return ("%s: %s"):format(e.file, e.err)
    end, discover_errors)
    vim.health.error(("%d autodiscovered file(s) failed to load"):format(#discover_errors), lines)
  else
    vim.health.ok("all autodiscovered files loaded without error")
  end
end

function M.check()
  vim.health.start("yaml-schema-selector.nvim")

  if vim.fn.has("nvim-0.11") == 0 then
    vim.health.error("Neovim 0.11 or newer is required")
    return
  end
  vim.health.ok("Neovim version is supported")

  local cfg = require("yaml-schema-selector").config
  if not cfg then
    vim.health.error("setup() has not been called")
    return
  end
  vim.health.ok(
    ("configured for LSP client `%s` with %d schema alias(es)"):format(cfg.server_name, vim.tbl_count(cfg.schemas))
  )

  check_treesitter(cfg)
  check_server(cfg)
  check_current_buffer()
  check_registry(cfg)
end

return M
