local yss = require("yaml-schema-selector")
local registry = require("yaml-schema-selector.registry")
local discover = require("yaml-schema-selector.discover")
local status_cache = require("yaml-schema-selector.status_cache")

describe("yaml-schema-selector public introspection API", function()
  before_each(function()
    registry.reset()
    discover.reset()
    status_cache.reset()
    yss.setup({ discover = false })
  end)

  describe("registrations()", function()
    it("lists select-based and matcher-based registrations with priority and kind", function()
      registry.register({ name = "a", priority = 80, select = function() end })
      registry.register({ name = "b", matcher = function() end, schema = "x" })
      local list = yss.registrations()
      assert.equals(2, #list)
      assert.equals("a", list[1].name)
      assert.equals(80, list[1].priority)
      assert.equals("select", list[1].kind)
      assert.is_false(list[1].discovered)
      assert.equals("b", list[2].name)
      assert.equals("matcher", list[2].kind)
    end)

    it("omits schemas-only registrations (no select/matcher)", function()
      registry.register({ name = "aliases-only", schemas = { a = "b" } })
      assert.same({}, yss.registrations())
    end)
  end)

  describe("schemas()", function()
    it("merges cfg.schemas over registry-contributed aliases", function()
      registry.register({ name = "contrib", schemas = { gh = "https://from-registry.example.com" } })
      yss.setup({ discover = false, schemas = { gh = "https://from-setup.example.com" } })
      assert.equals("https://from-setup.example.com", yss.schemas().gh)
    end)
  end)

  describe("statusline()", function()
    it("returns nil before any resolution has happened", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      assert.is_nil(yss.statusline(bufnr))
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("reverse-looks-up an alias name for the label", function()
      yss.setup({ discover = false, schemas = { gh = "https://example.com/gh.json" } })
      local bufnr = vim.api.nvim_create_buf(false, true)
      status_cache.set(bufnr, {
        schema = "https://example.com/gh.json",
        source = "gh",
        uri = "file:///a.yaml",
        path = "/a.yaml",
      })
      local s = yss.statusline(bufnr)
      assert.equals("gh", s.label)
      assert.equals("gh", s.source)
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("falls back to the basename when the schema is not an alias", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      status_cache.set(bufnr, {
        schema = "file:///schemas/house.json",
        source = "house",
        uri = "file:///a.yaml",
        path = "/a.yaml",
      })
      local s = yss.statusline(bufnr)
      assert.equals("house.json", s.label)
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)
end)
