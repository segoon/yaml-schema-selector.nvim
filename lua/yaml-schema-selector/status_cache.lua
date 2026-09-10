-- Per-buffer cache of the last schema resolution, kept up to date as a side
-- effect of real `custom/schema/request` handling (lsp.lua). This is what
-- makes `statusline()` safe to call from a redraw hot path: it never
-- re-runs the selector chain, it just reads whatever was cached last.

local M = {}

---@class yss.StatusEntry
---@field schema string|string[]|nil
---@field source string|nil
---@field uri string
---@field path string

---@type table<integer, yss.StatusEntry>
local cache = {}

---@type integer|nil
local augroup = nil

local function ensure_augroup()
  if augroup then
    return
  end
  augroup = vim.api.nvim_create_augroup("YamlSchemaSelectorStatusCache", { clear = true })
  vim.api.nvim_create_autocmd({ "BufDelete", "BufWipeout" }, {
    group = augroup,
    callback = function(args)
      cache[args.buf] = nil
    end,
  })
end

---Record the last resolution for a buffer.
---@param bufnr integer
---@param entry yss.StatusEntry
function M.set(bufnr, entry)
  ensure_augroup()
  cache[bufnr] = entry
end

---Look up the last resolution for a buffer, or nil if none has happened yet.
---@param bufnr integer
---@return yss.StatusEntry|nil
function M.get(bufnr)
  return cache[bufnr]
end

---Forget all cached entries. Used by tests.
function M.reset()
  cache = {}
end

return M
