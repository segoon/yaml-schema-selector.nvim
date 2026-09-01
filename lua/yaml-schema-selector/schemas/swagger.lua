-- Built-in selector: Swagger 2.0 documents, detected by content.
-- Autodiscovered by lua/yaml-schema-selector/discover.lua; registered as "swagger".

return {
  matcher = function(ctx)
    local doc = ctx.yaml()
    return doc ~= nil and doc.swagger == "2.0"
  end,
  schema = "swagger_2_0",
  schemas = {
    swagger_2_0 = "https://raw.githubusercontent.com/OAI/OpenAPI-Specification/main/schemas/v2.0/schema.json",
  },
}
