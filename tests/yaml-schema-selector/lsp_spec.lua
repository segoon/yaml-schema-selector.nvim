local lsp = require("yaml-schema-selector.lsp")
local config = require("yaml-schema-selector.config")

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
    local cfg = config.build({ select = function() end })
    local client = make_client(1)
    lsp.attach(cfg, client)
    assert.is_function(client.handlers[lsp.SCHEMA_REQUEST])
  end)

  it("sends the registration and a didChangeConfiguration notification", function()
    local cfg = config.build({ select = function() end })
    local client = make_client(2)
    lsp.attach(cfg, client)

    local methods = vim.tbl_map(function(n)
      return n.method
    end, client._notifications)
    assert.same({ lsp.REGISTER_NOTIFICATION, "workspace/didChangeConfiguration" }, methods)
  end)

  it("is a no-op the second time for the same client id", function()
    local cfg = config.build({ select = function() end })
    local client = make_client(3)
    assert.is_true(lsp.attach(cfg, client))
    assert.is_false(lsp.attach(cfg, client))
    assert.equals(2, #client._notifications)
  end)

  it("the installed handler returns vim.NIL for a selector that opts out", function()
    local cfg = config.build({
      select = function()
        return nil
      end,
    })
    local client = make_client(4)
    lsp.attach(cfg, client)

    local path = vim.fn.tempname() .. ".yaml"
    local uri = vim.uri_from_fname(path)
    local result = client.handlers[lsp.SCHEMA_REQUEST](nil, { uri })
    assert.equals(vim.NIL, result)
  end)
end)
