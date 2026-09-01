-- Built-in selector: OpenAPI 3.0/3.1 documents, detected by content.
-- Autodiscovered by lua/yaml-schema-selector/discover.lua; registered as "openapi".

return {
  matcher = function(ctx)
    local doc = ctx.yaml()
    return type(doc) == "table"
      and type(doc.openapi) == "string"
      and (doc.openapi:match("^3%.0") or doc.openapi:match("^3%.1")) ~= nil
  end,
  schema = function(ctx)
    local version = ctx.yaml().openapi
    if version:match("^3%.1") then
      return "openapi_3_1"
    end
    return "openapi_3_0"
  end,
  schemas = {
    openapi_3_0 = "https://raw.githubusercontent.com/OAI/OpenAPI-Specification/main/schemas/v3.0/schema.json",
    openapi_3_1 = "https://raw.githubusercontent.com/OAI/OpenAPI-Specification/main/schemas/v3.1/schema.json",
  },
}
