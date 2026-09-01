-- Built-in selector for Arcadia C35 codegen modules.

local c35 = require("yaml-schema-selector.c35")

c35.setup()

return {
  matcher = c35.matches,
  schema = c35.schema,
}
