local lsp = require("yaml-schema-selector.lsp")
local config = require("yaml-schema-selector.config")
local registry = require("yaml-schema-selector.registry")
local status_cache = require("yaml-schema-selector.status_cache")

---A minimal stand-in for `vim.lsp.Client`, just enough for `lsp.attach`.
---@param id integer
---@return table
local function make_client(id)
  local notifications = {}
  return {
    id = id,
    name = "yamlls",
    root_dir = "/root",
    handlers = {},
    notify = function(_self, method, params)
      table.insert(notifications, { method = method, params = params })
    end,
    _notifications = notifications,
  }
end

describe("lsp.attach", function()
  before_each(function()
    lsp.reset()
  end)

  it("installs the schema request handler", function()
    local cfg = config.build({})
    local client = make_client(1)
    lsp.attach(cfg, client)
    assert.is_function(client.handlers[lsp.SCHEMA_REQUEST])
  end)

  it("sends the registration and a didChangeConfiguration notification", function()
    local cfg = config.build({})
    local client = make_client(2)
    lsp.attach(cfg, client)

    local methods = vim.tbl_map(function(n)
      return n.method
    end, client._notifications)
    assert.same({ lsp.REGISTER_NOTIFICATION, "workspace/didChangeConfiguration" }, methods)
  end)

  it("is a no-op the second time for the same client id", function()
    local cfg = config.build({})
    local client = make_client(3)
    assert.is_true(lsp.attach(cfg, client))
    assert.is_false(lsp.attach(cfg, client))
    assert.equals(2, #client._notifications)
  end)

  it("the installed handler returns vim.NIL when no registration matches", function()
    local cfg = config.build({})
    local client = make_client(4)
    lsp.attach(cfg, client)

    local path = vim.fn.tempname() .. ".yaml"
    local uri = vim.uri_from_fname(path)
    local result = client.handlers[lsp.SCHEMA_REQUEST](nil, { uri })
    assert.equals(vim.NIL, result)
  end)

  describe("resolution event and status cache", function()
    before_each(function()
      registry.reset()
      status_cache.reset()
    end)

    it("fires YamlSchemaResolved and populates the status cache on a match", function()
      local cfg = config.build({})
      local client = make_client(5)
      lsp.attach(cfg, client)

      local bufnr = vim.api.nvim_create_buf(false, true)
      local path = vim.fn.tempname() .. ".yaml"
      vim.api.nvim_buf_set_name(bufnr, path)
      local uri = vim.uri_from_fname(path)

      registry.register({
        name = "gh",
        select = function()
          return "https://example.com/gh.json"
        end,
      })

      local seen
      local id = vim.api.nvim_create_autocmd("User", {
        pattern = lsp.RESOLVED_EVENT,
        callback = function(args)
          seen = args.data
        end,
      })

      local result = client.handlers[lsp.SCHEMA_REQUEST](nil, { uri })
      vim.api.nvim_del_autocmd(id)

      assert.equals("https://example.com/gh.json", result)
      assert.is_not_nil(seen)
      assert.equals(bufnr, seen.bufnr)
      assert.equals(uri, seen.uri)
      assert.equals("https://example.com/gh.json", seen.schema)
      assert.equals("gh", seen.source)

      local cached = status_cache.get(bufnr)
      assert.is_not_nil(cached)
      assert.equals("https://example.com/gh.json", cached.schema)
      assert.equals("gh", cached.source)

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("fires YamlSchemaResolved with a nil schema/source when nothing matches", function()
      local cfg = config.build({})
      local client = make_client(6)
      lsp.attach(cfg, client)

      local path = vim.fn.tempname() .. ".yaml"
      local uri = vim.uri_from_fname(path)

      local seen
      local id = vim.api.nvim_create_autocmd("User", {
        pattern = lsp.RESOLVED_EVENT,
        callback = function(args)
          seen = args.data
        end,
      })

      client.handlers[lsp.SCHEMA_REQUEST](nil, { uri })
      vim.api.nvim_del_autocmd(id)

      assert.is_not_nil(seen)
      assert.is_nil(seen.schema)
      assert.is_nil(seen.source)
    end)
  end)
end)
