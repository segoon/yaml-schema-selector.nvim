-- Turns whatever the user's `select` function returned into schema URIs the
-- yaml-language-server understands.

local M = {}

---Reserved keywords the server special-cases; they must reach it verbatim.
---@type table<string, true>
local RESERVED = {
  kubernetes = true,
}

---Matches an absolute URI such as `https://…`, `file://…`.
local URI_PATTERN = "^%a[%w+.%-]*://"

---Resolve a single value: alias lookup, then URI passthrough, then path handling.
---
---Alias substitution happens exactly once: the substituted value is never looked
---up again, which makes alias cycles impossible by construction.
---@param value string
---@param schemas table<string, string> Alias table.
---@param base_dir string|nil Directory relative paths are resolved against.
---@return string
function M.resolve_one(value, schemas, base_dir)
  local resolved = schemas[value] or value

  if RESERVED[resolved] or resolved:match(URI_PATTERN) then
    return resolved
  end

  local path = vim.fn.expand(resolved)
  if not vim.startswith(path, "/") then
    path = vim.fs.joinpath(base_dir or vim.uv.cwd() or ".", path)
  end

  return vim.uri_from_fname(vim.fs.normalize(path))
end

---Normalize a selector result into the response the server expects.
---Returns `vim.NIL` for "no schema" so the server falls back to its own
---resolution chain; a plain `nil` would make Neovim's RPC layer raise.
---@param selection yss.Selection
---@param schemas table<string, string> Alias table.
---@param base_dir string|nil Directory relative paths are resolved against.
---@return string|string[]|vim.NIL
function M.normalize(selection, schemas, base_dir)
  if type(selection) == "string" then
    return M.resolve_one(selection, schemas, base_dir)
  end

  if type(selection) == "table" then
    local out = {}
    for _, value in ipairs(selection) do
      if type(value) == "string" then
        out[#out + 1] = M.resolve_one(value, schemas, base_dir)
      end
    end
    if #out > 0 then
      return out
    end
  end

  return vim.NIL
end

return M
