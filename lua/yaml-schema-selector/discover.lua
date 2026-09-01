-- Autodiscovery of schema selectors: scans 'runtimepath' for
-- lua/yaml-schema-selector/schemas/**/*.lua and registers what they return.
--
-- This is purely a batch caller of registry.register() -- it adds no new
-- registration mechanics, only the scanning, default naming, and cleanup of
-- entries whose source file has since disappeared.

local registry = require("yaml-schema-selector.registry")

local M = {}

local RTP_PATTERN = "lua/yaml-schema-selector/schemas/**/*.lua"
local ANCHOR = "/lua/yaml-schema-selector/schemas/"
local NAMESPACE = "yaml-schema-selector.schemas."

---@class yss.DiscoverError
---@field file string Absolute path of the file that failed.
---@field err string Error message.

---@type table<string, true>
local discovered = {}
---@type table<string, yss.Registration>
local refs = {}
---@type yss.DiscoverError[]
local errors = {}

---Derive a require()-able module name from an absolute file path.
---@param path string
---@return string|nil modname
local function modname_from_path(path)
  local normalized = path:gsub("\\", "/")
  local idx = normalized:find(ANCHOR, 1, true)
  if not idx then
    return nil
  end
  local rel = normalized:sub(idx + #ANCHOR)
  rel = rel:gsub("%.lua$", ""):gsub("/", ".")
  return NAMESPACE .. rel
end

---@param file string
---@param err any
local function record_error(file, err)
  errors[#errors + 1] = { file = file, err = tostring(err) }
end

---Re-scan 'runtimepath' for lua/yaml-schema-selector/schemas/**/*.lua files
---and (re-)register what they return. Safe to call repeatedly: a name
---registered by a previous discover() run whose source file has since
---disappeared is unregistered, unless something else has re-registered that
---same name in the meantime.
function M.discover()
  local files = vim.api.nvim_get_runtime_file(RTP_PATTERN, true)

  local new_discovered = {} ---@type table<string, true>
  local new_refs = {} ---@type table<string, yss.Registration>
  local new_errors = {} ---@type yss.DiscoverError[]
  local seen_modnames = {} ---@type table<string, string>

  errors = new_errors

  for _, path in ipairs(files) do
    local modname = modname_from_path(path)
    local real_path = vim.fn.resolve(vim.fn.fnamemodify(path, ":p"))
    -- A modname seen before with the same real path means the same file was
    -- reached twice through different rtp entries (e.g. a relative "." entry
    -- and its absolute equivalent); not a real collision, so it's ignored.
    if not modname then
      record_error(path, "could not derive a module name from this path")
    elseif seen_modnames[modname] and seen_modnames[modname] ~= real_path then
      record_error(path, ("duplicate module name %q also provided by %s"):format(modname, seen_modnames[modname]))
    elseif not seen_modnames[modname] then
      seen_modnames[modname] = real_path
      package.loaded[modname] = nil
      local ok, result = pcall(require, modname)
      if not ok then
        record_error(path, result)
      elseif type(result) ~= "table" then
        record_error(path, ("expected a table (registration or list of registrations), got %s"):format(type(result)))
      else
        local list = (result[1] ~= nil) and result or { result }
        local base = modname:sub(#NAMESPACE + 1)
        for i, spec in ipairs(list) do
          if type(spec) ~= "table" then
            record_error(path, ("entry %d did not return a table"):format(i))
          else
            if spec.name == nil then
              spec = vim.tbl_extend("force", spec, {
                name = (#list > 1) and (base .. "#" .. i) or base,
              })
            end
            local reg_ok, reg_err = pcall(registry.register, spec)
            if not reg_ok then
              record_error(path, reg_err)
            else
              new_discovered[spec.name] = true
              new_refs[spec.name] = spec
            end
          end
        end
      end
    end
  end

  for name in pairs(discovered) do
    if not new_discovered[name] and registry.get(name) == refs[name] then
      registry.unregister(name)
    end
  end

  discovered = new_discovered
  refs = new_refs
  errors = new_errors

  if #errors > 0 then
    vim.notify(
      ("yaml-schema-selector: %d autodiscovered file(s) failed to load, see :checkhealth"):format(#errors),
      vim.log.levels.WARN
    )
  end
end

---Names currently registered as a result of the last discover() call.
---@return table<string, true>
function M.discovered()
  return discovered
end

---Problems from the last discover() run.
---@return yss.DiscoverError[]
function M.errors()
  return errors
end

---Forget all discovery bookkeeping (does not touch the registry). Used by tests.
function M.reset()
  discovered = {}
  refs = {}
  errors = {}
end

return M
