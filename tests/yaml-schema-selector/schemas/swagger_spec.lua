local swagger = require("yaml-schema-selector.schemas.swagger")

local function ctx_for(doc)
  return {
    yaml = function()
      return doc
    end,
  }
end

describe("schemas/swagger.lua", function()
  it("matches a Swagger 2.0 document", function()
    assert.is_true(swagger.matcher(ctx_for({ swagger = "2.0" })))
  end)

  it("does not match a document without a swagger key", function()
    assert.falsy(swagger.matcher(ctx_for({ openapi = "3.0.0" })))
  end)

  it("does not match a document with a different swagger value", function()
    assert.falsy(swagger.matcher(ctx_for({ swagger = "1.2" })))
  end)

  it("does not match when there is no parsed document", function()
    assert.falsy(swagger.matcher(ctx_for(nil)))
  end)

  it("resolves through the schemas alias table to the swagger 2.0 URL", function()
    assert.equals("swagger_2_0", swagger.schema)
    assert.equals(
      "https://raw.githubusercontent.com/OAI/OpenAPI-Specification/main/schemas/v2.0/schema.json",
      swagger.schemas.swagger_2_0
    )
  end)
end)
