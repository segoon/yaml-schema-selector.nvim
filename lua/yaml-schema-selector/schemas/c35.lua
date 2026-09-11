-- Built-in selector for Arcadia C35 codegen modules, with dynamic schema
-- generation.

local M = {}

local GENERATOR = "scripts/generate-c35-cmy-schema.py"
local CACHE_SUBDIR = "yaml-schema-selector/c35"

---@class yss.C35Context
---@field path string
---@field filename string
---@field bufnr integer|nil

---@class yss.C35JobResult
---@field code integer
---@field stdout string
---@field stderr string

---@class yss.C35State
---@field ctx yss.C35Context
---@field fingerprint string
---@field generation integer
---@field running boolean
---@field pending boolean
---@field failed boolean
---@field uri string|nil

---@class yss.C35Dependencies
---@field fingerprint fun(path: string): string
---@field generator fun(): string|nil
---@field run fun(command: string[], opts: table, callback: fun(result: yss.C35JobResult))
---@field cache fun(output: string): string
---@field refresh fun()
---@field notify fun(message: string)

---@type table<string, yss.C35State>
local states = {}

---@type table<string, true>
local reported = {}

---@param message string
local function default_notify(message)
  vim.notify("yaml-schema-selector: " .. message, vim.log.levels.ERROR)
end

---@param path string
---@return string
local function default_fingerprint(path)
  local stat = vim.uv.fs_stat(path)
  if not stat then
    return "missing"
  end
  return table.concat({ stat.size, stat.mtime.sec, stat.mtime.nsec }, ":")
end

---@return string|nil
local function default_generator()
  return vim.api.nvim_get_runtime_file(GENERATOR, false)[1]
end

---@param command string[]
---@param opts table
---@param callback fun(result: yss.C35JobResult)
local function default_run(command, opts, callback)
  vim.system(command, { cwd = opts.cwd, text = true }, function(result)
    vim.schedule(function()
      callback(result)
    end)
  end)
end

---@param output string
---@return string uri
local function default_cache(output)
  -- Normalize the generator output so writefile() cannot translate embedded
  -- newlines to NUL bytes and escaped Unicode is stored as readable UTF-8.
  local encoded = vim.json.encode(vim.json.decode(output))

  local cache_dir = vim.fs.joinpath(vim.fn.stdpath("cache"), CACHE_SUBDIR)
  vim.fn.mkdir(cache_dir, "p")
  local path = vim.fs.joinpath(cache_dir, vim.fn.sha256(encoded) .. ".json")
  local ok, result = pcall(vim.fn.writefile, { encoded }, path, "b")
  if not ok or result ~= 0 then
    error(("failed to write %s: %s"):format(path, ok and "writefile returned " .. result or result), 0)
  end
  return vim.uri_from_fname(path)
end

local function default_refresh()
  local selector = package.loaded["yaml-schema-selector"]
  if not selector or not selector.config then
    return
  end
  local lsp = require("yaml-schema-selector.lsp")
  for _, client in ipairs(lsp.clients(selector.config)) do
    lsp.revalidate(client)
  end
end

---@type yss.C35Dependencies
local defaults = {
  fingerprint = default_fingerprint,
  generator = default_generator,
  run = default_run,
  cache = default_cache,
  refresh = default_refresh,
  notify = default_notify,
}

---@type yss.C35Dependencies
local dependencies = vim.deepcopy(defaults)

---@param message string
local function notify_once(message)
  if reported[message] then
    return
  end
  reported[message] = true
  dependencies.notify(message)
end

---@param state yss.C35State
---@param message string
local function fail(state, message)
  state.running = false
  state.failed = true
  state.uri = nil
  notify_once(message)
end

local ensure

---@param state yss.C35State
local function start(state)
  local generator = dependencies.generator()
  if not generator then
    fail(state, ("C35 schema generator was not found on 'runtimepath' (%s)"):format(GENERATOR))
    return
  end

  local token = state.generation
  state.running = true
  state.failed = false
  local command = { "ya", "tool", "tt", "python", generator, state.ctx.path }
  local opts = { cwd = vim.fs.dirname(state.ctx.path) }

  local ok, err = pcall(dependencies.run, command, opts, function(result)
    if token ~= state.generation then
      state.running = false
      if state.pending then
        state.pending = false
        ensure(state.ctx, false)
      end
      return
    end

    if result.code ~= 0 then
      local detail = (result.stderr or ""):gsub("%s+$", "")
      fail(
        state,
        ("failed to generate a C35 schema for %s%s"):format(state.ctx.path, detail == "" and "" or ": " .. detail)
      )
      return
    end

    local cache_ok, uri = pcall(dependencies.cache, result.stdout or "")
    if not cache_ok then
      fail(state, ("failed to cache the C35 schema for %s: %s"):format(state.ctx.path, uri))
      return
    end

    state.running = false
    state.failed = false
    state.uri = uri
    dependencies.refresh()
  end)

  if not ok then
    fail(state, ("failed to start the C35 schema generator for %s: %s"):format(state.ctx.path, err))
  end
end

---@param ctx yss.C35Context
---@param force boolean
---@return string|nil
ensure = function(ctx, force)
  local fingerprint = dependencies.fingerprint(ctx.path)
  local state = states[ctx.path]
  if not state then
    state = {
      ctx = ctx,
      fingerprint = fingerprint,
      generation = 1,
      running = false,
      pending = false,
      failed = false,
      uri = nil,
    }
    states[ctx.path] = state
  else
    state.ctx = ctx
    if force or state.fingerprint ~= fingerprint then
      state.fingerprint = fingerprint
      state.generation = state.generation + 1
      state.uri = nil
      state.failed = false
      if state.running then
        state.pending = true
        return nil
      end
    end
  end

  if state.uri or state.failed then
    return state.uri
  end
  if not state.running then
    start(state)
  end
  return nil
end

---@param ctx yss.C35Context
---@return boolean
function M.matches(ctx)
  return ctx.filename == "codegen-module.yaml"
end

---Return a ready schema URI, starting asynchronous generation when needed.
---@param ctx yss.C35Context
---@return string|nil
function M.schema(ctx)
  return ensure(ctx, false)
end

---Invalidate and regenerate one module after it is written.
---@param path string
---@param bufnr integer|nil
function M.regenerate(path, bufnr)
  ensure({ path = path, filename = vim.fs.basename(path), bufnr = bufnr }, true)
end

---Invalidate every known module. Used by the public manual refresh command so
---changes made only to referenced plugin files are incorporated.
function M.invalidate_all()
  local contexts = {}
  for _, state in pairs(states) do
    contexts[#contexts + 1] = state.ctx
  end
  for _, ctx in ipairs(contexts) do
    ensure(ctx, true)
  end
end

---Install the save hook used by the built-in registration.
function M.setup()
  local group = vim.api.nvim_create_augroup("YamlSchemaSelectorC35", { clear = true })
  vim.api.nvim_create_autocmd("BufWritePost", {
    group = group,
    pattern = "codegen-module.yaml",
    callback = function(args)
      local path = vim.api.nvim_buf_get_name(args.buf)
      if path ~= "" then
        M.regenerate(path, args.buf)
      end
    end,
  })
end

---Reset generation state and dependencies. Used by tests.
function M.reset()
  states = {}
  reported = {}
  dependencies = vim.deepcopy(defaults)
end

---Override side-effecting dependencies. Used by tests.
---@param overrides table<string, any>
function M.set_dependencies(overrides)
  dependencies = vim.tbl_extend("force", dependencies, overrides)
end

M.matcher = M.matches
M.refresh = M.invalidate_all

M.setup()

return M
