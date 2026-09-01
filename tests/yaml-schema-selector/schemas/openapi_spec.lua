local openapi = require("yaml-schema-selector.schemas.openapi")

local function ctx_for(doc)
  return {
    yaml = function()
      return doc
    end,
  }
end

describe("schemas/openapi.lua", function()
  it("matches an OpenAPI 3.0.x document", function()
    assert.is_true(openapi.matcher(ctx_for({ openapi = "3.0.3" })))
  end)

  it("matches an OpenAPI 3.1.x document", function()
    assert.is_true(openapi.matcher(ctx_for({ openapi = "3.1.0" })))
  end)

  it("does not match a Swagger 2.0 document", function()
    assert.falsy(openapi.matcher(ctx_for({ swagger = "2.0" })))
  end)

  it("does not match an unrecognized openapi version", function()
    assert.falsy(openapi.matcher(ctx_for({ openapi = "3.2.0" })))
  end)

  it("does not match a non-string openapi field", function()
    assert.falsy(openapi.matcher(ctx_for({ openapi = 3.0 })))
  end)

  it("does not match when there is no parsed document", function()
    assert.falsy(openapi.matcher(ctx_for(nil)))
  end)

  it("resolves to the 3.0 alias for a 3.0.x document", function()
    assert.equals("openapi_3_0", openapi.schema(ctx_for({ openapi = "3.0.3" })))
  end)

  it("resolves to the 3.1 alias for a 3.1.x document", function()
    assert.equals("openapi_3_1", openapi.schema(ctx_for({ openapi = "3.1.0" })))
  end)

  it("contributes both alias URLs", function()
    assert.equals(
      "https://raw.githubusercontent.com/OAI/OpenAPI-Specification/main/schemas/v3.0/schema.json",
      openapi.schemas.openapi_3_0
    )
    assert.equals(
      "https://raw.githubusercontent.com/OAI/OpenAPI-Specification/main/schemas/v3.1/schema.json",
      openapi.schemas.openapi_3_1
    )
  end)
end)
