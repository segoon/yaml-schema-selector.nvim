local registry = require("yaml-schema-selector.registry")

describe("registry.register", function()
  before_each(function()
    registry.reset()
  end)

  it("errors without a name", function()
    assert.has_error(function()
      registry.register({ select = function() end })
    end)
  end)

  it("errors when neither select, matcher+schema, nor schemas is given", function()
    assert.has_error(function()
      registry.register({ name = "empty" })
    end)
  end)

  it("errors when select and matcher are both given", function()
    assert.has_error(function()
      registry.register({ name = "both", select = function() end, matcher = function() end, schema = "x" })
    end)
  end)

  it("errors when matcher is given without schema", function()
    assert.has_error(function()
      registry.register({ name = "half", matcher = function() end })
    end)
  end)

  it("errors when a schemas value is not a string", function()
    assert.has_error(function()
      registry.register({ name = "bad-type", schemas = { a = 1 } })
    end)
  end)

  it("errors when a schemas value is a truncated URI", function()
    assert.has_error(function()
      registry.register({ name = "bad-uri", schemas = { a = "https://" } })
    end)
  end)

  it("allows a schemas-only registration", function()
    registry.register({ name = "aliases-only", schemas = { a = "https://example.com/a.json" } })
    assert.same(
      {},
      vim.tbl_map(function(e)
        return e.name
      end, registry.sorted())
    )
    assert.same({ a = "https://example.com/a.json" }, registry.schemas())
  end)

  it("replaces a previous registration with the same name", function()
    registry.register({
      name = "dup",
      select = function()
        return "first"
      end,
    })
    registry.register({
      name = "dup",
      select = function()
        return "second"
      end,
    })
    local sorted = registry.sorted()
    assert.equals(1, #sorted)
    assert.equals("second", sorted[1].select())
  end)
end)

describe("registry.unregister", function()
  before_each(function()
    registry.reset()
  end)

  it("removes a registration", function()
    registry.register({ name = "gone", select = function() end })
    registry.unregister("gone")
    assert.same({}, registry.sorted())
  end)

  it("is a no-op for an unknown name", function()
    registry.unregister("nope")
  end)
end)

describe("registry.sorted", function()
  before_each(function()
    registry.reset()
  end)

  it("orders by priority, highest first", function()
    registry.register({ name = "low", priority = 1, select = function() end })
    registry.register({ name = "high", priority = 100, select = function() end })
    registry.register({ name = "mid", priority = 50, select = function() end })
    local names = vim.tbl_map(function(e)
      return e.name
    end, registry.sorted())
    assert.same({ "high", "mid", "low" }, names)
  end)

  it("defaults to priority 50 and breaks ties by registration order", function()
    registry.register({ name = "first", select = function() end })
    registry.register({ name = "second", select = function() end })
    local names = vim.tbl_map(function(e)
      return e.name
    end, registry.sorted())
    assert.same({ "first", "second" }, names)
  end)
end)

describe("registry.schemas", function()
  before_each(function()
    registry.reset()
  end)

  it("merges alias tables from every registration", function()
    registry.register({ name = "a", schemas = { x = "1" } })
    registry.register({ name = "b", schemas = { y = "2" } })
    assert.same({ x = "1", y = "2" }, registry.schemas())
  end)

  it("resolves collisions in favor of the higher-priority registration", function()
    registry.register({ name = "low", priority = 1, schemas = { x = "low" } })
    registry.register({ name = "high", priority = 100, schemas = { x = "high" } })
    assert.same({ x = "high" }, registry.schemas())
  end)
end)
