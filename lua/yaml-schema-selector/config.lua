-- Configuration defaults and validation for yaml-schema-selector.nvim.

local aliases = require("yaml-schema-selector.aliases")

---Context handed to the user's `select` function.
---@class yss.Context
---@field uri string Document URI as sent by the language server.
---@field path string Absolute filesystem path of the document.
---@field filename string Basename of the document.
---@field bufnr integer|nil Buffer handle, or nil when the document is not loaded.
---@field filetype string|nil Filetype of the buffer, or nil when not loaded.
---@field root_dir string|nil Root directory of the language server client.
---@field client_id integer Id of the language server client.
---@field schemas table<string, string> The configured schema aliases.
---@field lines fun(n?: integer): string[] First `n` lines (default: all). Lazy, memoized.
---@field yaml fun(): table|nil First YAML document as a Lua value. Lazy, memoized.
---@field yaml_documents fun(): table[] All `---`-separated documents. Lazy, memoized.

---What a selector may return: nil, an alias/URI/path, or a list of them.
---@alias yss.Selection string|string[]|nil

---@class yss.Config
---@field server_name string Name of the LSP client to layer onto.
---@field schemas table<string, string> Named aliases mapped to a URI, path or "kubernetes".
---@field max_parse_bytes integer Documents larger than this are not parsed by `ctx.yaml()`.
---@field discover boolean Autodiscover lua/yaml-schema-selector/schemas/**/*.lua on 'runtimepath'. Default: true.

local M = {}

---@type yss.Config
M.defaults = {
  server_name = "yamlls",
  schemas = {},
  max_parse_bytes = 1024 * 1024,
  discover = true,
}

---Merge user options over the defaults and validate the result.
---Raises a descriptive error when the configuration is unusable.
---@param opts table|nil
---@return yss.Config
function M.build(opts)
  opts = opts or {}
  if type(opts) ~= "table" then
    error("yaml-schema-selector: setup() expects a table, got " .. type(opts), 0)
  end

  local cfg = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts)

  if type(cfg.server_name) ~= "string" or cfg.server_name == "" then
    error("yaml-schema-selector: `server_name` must be a non-empty string", 0)
  end
  if type(cfg.schemas) ~= "table" then
    error("yaml-schema-selector: `schemas` must be a table", 0)
  end
  for name, value in pairs(cfg.schemas) do
    if type(name) ~= "string" or type(value) ~= "string" then
      error("yaml-schema-selector: `schemas` must map string names to string values", 0)
    end
    local ok, err = aliases.valid_target(value)
    if not ok then
      error(("yaml-schema-selector: `schemas.%s`: %s"):format(name, err), 0)
    end
  end
  if type(cfg.max_parse_bytes) ~= "number" or cfg.max_parse_bytes < 0 then
    error("yaml-schema-selector: `max_parse_bytes` must be a non-negative number", 0)
  end
  if type(cfg.discover) ~= "boolean" then
    error("yaml-schema-selector: `discover` must be a boolean", 0)
  end

  return cfg
end

return M
