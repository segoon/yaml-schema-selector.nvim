describe("built-in schemas", function()
  it("uses yaml-language-server's OpenAPI schema URL", function()
    local spec = require("yaml-schema-selector.schemas.openapi")

    assert.equals("https://www.schemastore.org/openapi-3.X.json", spec.schemas.openapi_3_0)
    assert.equals("https://www.schemastore.org/openapi-3.X.json", spec.schemas.openapi_3_1)
  end)

  it("uses yaml-language-server's Swagger schema URL", function()
    local spec = require("yaml-schema-selector.schemas.swagger")

    assert.equals("https://spec.openapis.org/oas/2.0/schema/2017-08-27", spec.schemas.swagger_2_0)
  end)
end)
