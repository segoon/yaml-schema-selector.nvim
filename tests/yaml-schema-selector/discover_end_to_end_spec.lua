-- Proves the built-in lua/yaml-schema-selector/schemas/{openapi,swagger}.lua
-- files are wired up correctly through the real discover()/registry path --
-- these are real files on the plugin's own rtp entry, not test fixtures.

local discover = require("yaml-schema-selector.discover")
local registry = require("yaml-schema-selector.registry")

local function ctx_for(doc)
  return {
    yaml = function()
      return doc
    end,
  }
end

describe("built-in openapi/swagger selectors", function()
  before_each(function()
    registry.reset()
    discover.reset()
    discover.discover()
  end)

  after_each(function()
    registry.reset()
    discover.reset()
  end)

  it("discovers both as built-in selectors", function()
    assert.is_not_nil(registry.get("openapi"))
    assert.is_not_nil(registry.get("swagger"))
    assert.same({}, discover.errors())
  end)

  it("resolves an openapi 3.0 document through the registered entry", function()
    local entry = registry.get("openapi")
    local ctx = ctx_for({ openapi = "3.0.1" })
    assert.is_true(entry.matcher(ctx))
    assert.equals("openapi_3_0", entry.schema(ctx))
  end)

  it("resolves an openapi 3.1 document through the registered entry", function()
    local entry = registry.get("openapi")
    local ctx = ctx_for({ openapi = "3.1.0" })
    assert.is_true(entry.matcher(ctx))
    assert.equals("openapi_3_1", entry.schema(ctx))
  end)

  it("resolves a swagger 2.0 document through the registered entry", function()
    local entry = registry.get("swagger")
    local ctx = ctx_for({ swagger = "2.0" })
    assert.is_true(entry.matcher(ctx))
    assert.equals("swagger_2_0", entry.schema)
  end)

  it("contributes both aliases into the merged schemas table", function()
    local schemas = registry.schemas()
    assert.equals(
      "https://raw.githubusercontent.com/OAI/OpenAPI-Specification/main/schemas/v3.0/schema.json",
      schemas.openapi_3_0
    )
    assert.equals(
      "https://raw.githubusercontent.com/OAI/OpenAPI-Specification/main/schemas/v2.0/schema.json",
      schemas.swagger_2_0
    )
  end)
end)
