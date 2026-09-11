-- Decoupled registration of schema selectors and aliases.
--
-- register() writes into a module-level table, so it works whether it runs
-- before or after setup() -- or whether setup() ever runs at all. This is
-- how other plugins are meant to contribute schema knowledge without
-- fighting over the single `select` function a caller-owned setup() would
-- otherwise require.

local aliases = require("yaml-schema-selector.aliases")

local M = {}

---A registered contribution. Exactly one of `select` or `matcher`+`schema`
---may be given (or neither, for a `schemas`-only registration).
---@class yss.Registration
---@field name string Unique id. Re-registering the same name replaces the previous entry.
---@field priority integer|nil Higher runs first; ties broken by registration order. Default 50.
---@field select fun(ctx: yss.Context): yss.Selection|nil Full selector, same contract as the old `setup()` `select`.
---@field matcher fun(ctx: yss.Context): any Predicate; paired with `schema`.
---@field schema yss.Selection|fun(ctx: yss.Context): yss.Selection|nil Answer used when `matcher` returns truthy.
---@field schemas table<string, string>|nil Alias contributions merged into the shared alias table.
---@field refresh fun()|nil Called by `M.refresh()` to invalidate state a buffer changedtick can't reach.

---@type table<string, yss.Registration>
local entries = {}

---@type table<string, integer>
local order = {}
local seq = 0

---@param spec yss.Registration
local function validate(spec)
  if type(spec) ~= "table" then
    error("yaml-schema-selector.register: expected a table, got " .. type(spec), 0)
  end
  if type(spec.name) ~= "string" or spec.name == "" then
    error("yaml-schema-selector.register: `name` is required and must be a non-empty string", 0)
  end
  if spec.select ~= nil and type(spec.select) ~= "function" then
    error("yaml-schema-selector.register: `select` must be a function", 0)
  end
  if spec.matcher ~= nil and type(spec.matcher) ~= "function" then
    error("yaml-schema-selector.register: `matcher` must be a function", 0)
  end
  if spec.refresh ~= nil and type(spec.refresh) ~= "function" then
    error("yaml-schema-selector.register: `refresh` must be a function", 0)
  end
  if (spec.matcher ~= nil) ~= (spec.schema ~= nil) then
    error("yaml-schema-selector.register: `matcher` and `schema` must be given together", 0)
  end
  if spec.select and spec.matcher then
    error("yaml-schema-selector.register: give either `select`, or `matcher` + `schema`, not both", 0)
  end
  if not spec.select and not spec.matcher and not spec.schemas then
    error("yaml-schema-selector.register: give `select`, `matcher` + `schema`, or `schemas`", 0)
  end
  if spec.priority ~= nil and type(spec.priority) ~= "number" then
    error("yaml-schema-selector.register: `priority` must be a number", 0)
  end
  if spec.schemas ~= nil then
    if type(spec.schemas) ~= "table" then
      error("yaml-schema-selector.register: `schemas` must be a table", 0)
    end
    for name, value in pairs(spec.schemas) do
      if type(name) ~= "string" or type(value) ~= "string" then
        error("yaml-schema-selector.register: `schemas` must map string names to string values", 0)
      end
      local ok, err = aliases.valid_target(value)
      if not ok then
        error(("yaml-schema-selector.register: `schemas.%s`: %s"):format(name, err), 0)
      end
    end
  end
end

---Register a schema selector, a set of schema aliases, or both.
---Safe to call at any time, independent of `setup()`.
---@param spec yss.Registration
function M.register(spec)
  validate(spec)
  entries[spec.name] = spec
  seq = seq + 1
  order[spec.name] = seq
end

---Remove a previously registered entry, if any. A no-op otherwise.
---@param name string
function M.unregister(name)
  entries[name] = nil
  order[name] = nil
end

---Look up a single registered entry by name, or nil.
---@param name string
---@return yss.Registration|nil
function M.get(name)
  return entries[name]
end

---Registered entries with a `select`/`matcher`, sorted by priority (higher
---first), ties broken by registration order.
---@return yss.Registration[]
function M.sorted()
  local list = {}
  for _, spec in pairs(entries) do
    if spec.select or spec.matcher then
      list[#list + 1] = spec
    end
  end
  table.sort(list, function(a, b)
    local pa, pb = a.priority or 50, b.priority or 50
    if pa ~= pb then
      return pa > pb
    end
    return order[a.name] < order[b.name]
  end)
  return list
end

---Alias table merged from every registration's `schemas`, in priority order.
---On a key collision, the higher-priority (or earlier-registered) value wins.
---@return table<string, string>
function M.schemas()
  local list = {}
  for _, spec in pairs(entries) do
    if spec.schemas then
      list[#list + 1] = spec
    end
  end
  table.sort(list, function(a, b)
    local pa, pb = a.priority or 50, b.priority or 50
    if pa ~= pb then
      return pa > pb
    end
    return order[a.name] < order[b.name]
  end)

  local merged = {}
  for _, spec in ipairs(list) do
    for k, v in pairs(spec.schemas) do
      if merged[k] == nil then
        merged[k] = v
      end
    end
  end
  return merged
end

---Call every registered entry's `refresh`, if any. Used to invalidate
---selector-owned state that a buffer changedtick can't reach on its own.
function M.refresh()
  for _, spec in pairs(entries) do
    if spec.refresh then
      spec.refresh()
    end
  end
end

---Forget all registrations. Used by tests.
function M.reset()
  entries = {}
  order = {}
  seq = 0
end

return M
