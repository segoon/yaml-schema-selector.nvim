-- Layers the custom schema provider onto an already-running yaml-language-server
-- client. Nothing here starts or configures the server.

local selector = require("yaml-schema-selector.selector")
local status_cache = require("yaml-schema-selector.status_cache")

local M = {}

---The server->client request the language server sends once a custom schema
---provider has been registered.
M.SCHEMA_REQUEST = "custom/schema/request"

---Fired as a `User` autocmd every time the server asks for a schema and gets
---an answer (or definitively doesn't). `data` is
---`{ bufnr, uri, path, schema, source }`; `schema`/`source` are `nil` when no
---registration answered. Also the point at which the `statusline()` cache is
---updated, so consumers may prefer reading that over listening here.
M.RESOLVED_EVENT = "YamlSchemaResolved"

---The notification that makes the server register us as its schema provider.
M.REGISTER_NOTIFICATION = "yaml/registerCustomSchemaRequest"

---Clients we have already layered onto, keyed by client id.
---@type table<integer, true>
local registered = {}

---@type integer|nil
local augroup = nil

---Forget all registrations. Used by tests and on re-`setup()`.
function M.reset()
  registered = {}
end

---Ask the server to re-pull its configuration, which makes it re-validate every
---open document and therefore re-query the schema provider.
---@param client vim.lsp.Client
function M.revalidate(client)
  client:notify("workspace/didChangeConfiguration", { settings = vim.empty_dict() })
end

---Install the schema provider on a client. Safe to call repeatedly.
---@param cfg yss.Config
---@param client vim.lsp.Client
---@return boolean attached True if this call performed the registration.
function M.attach(cfg, client)
  if registered[client.id] then
    return false
  end
  registered[client.id] = true

  client.handlers = client.handlers or {}
  client.handlers[M.SCHEMA_REQUEST] = function(_, params)
    local uri = selector.params_to_uri(params)
    if not uri then
      return vim.NIL
    end

    local detailed = selector.resolve_detailed(cfg, uri, client)
    local schema = nil
    if detailed.schema ~= vim.NIL then
      schema = detailed.schema
    end
    local path = vim.uri_to_fname(uri)
    local bufnr = selector.find_buf(path)

    local data = { bufnr = bufnr, uri = uri, path = path, schema = schema, source = detailed.source }
    if bufnr then
      status_cache.set(bufnr, { schema = schema, source = detailed.source, uri = uri, path = path })
    end
    vim.api.nvim_exec_autocmds("User", { pattern = M.RESOLVED_EVENT, data = data })

    return detailed.schema
  end

  client:notify(M.REGISTER_NOTIFICATION, vim.empty_dict())
  -- Documents opened before this point were resolved without the provider.
  M.revalidate(client)

  return true
end

---Every running client the plugin applies to.
---@param cfg yss.Config
---@return vim.lsp.Client[]
function M.clients(cfg)
  return vim.lsp.get_clients({ name = cfg.server_name })
end

---Wire up autocommands and pick up any client that is already running.
---@param cfg yss.Config
function M.setup(cfg)
  M.reset()

  augroup = vim.api.nvim_create_augroup("YamlSchemaSelector", { clear = true })

  vim.api.nvim_create_autocmd("LspAttach", {
    group = augroup,
    callback = function(args)
      local client = vim.lsp.get_client_by_id(args.data.client_id)
      if client and client.name == cfg.server_name then
        M.attach(cfg, client)
      end
    end,
  })

  vim.api.nvim_create_autocmd("LspDetach", {
    group = augroup,
    callback = function(args)
      local id = args.data.client_id
      -- The buffer being detached still counts at this point.
      local buffers = vim.lsp.get_buffers_by_client_id(id)
      if #buffers <= 1 then
        registered[id] = nil
      end
    end,
  })

  for _, client in ipairs(M.clients(cfg)) do
    M.attach(cfg, client)
  end
end

return M
