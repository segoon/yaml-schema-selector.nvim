local selector = require("yaml-schema-selector.selector")
local config = require("yaml-schema-selector.config")
local registry = require("yaml-schema-selector.registry")

local function has_parser()
  return pcall(vim.treesitter.get_string_parser, "a: b", "yaml")
end

---Create a scratch buffer backed by a real path (selector.lua locates buffers
---by matching normalized names, so the buffer needs a name that round-trips
---through `vim.uri_to_fname(vim.uri_from_fname(...))`).
---@param lines string[]
---@return integer bufnr
---@return string path
---@return string uri
local function make_buffer(lines)
  local path = vim.fn.tempname() .. ".yaml"
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(bufnr, path)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.bo[bufnr].filetype = "yaml"
  return bufnr, path, vim.uri_from_fname(path)
end

local fake_client = { id = 1, root_dir = "/root" }

describe("selector.params_to_uri", function()
  it("accepts a bare string", function()
    assert.equals("file:///a.yaml", selector.params_to_uri("file:///a.yaml"))
  end)

  it("accepts a one-element list (position-encoded param)", function()
    assert.equals("file:///a.yaml", selector.params_to_uri({ "file:///a.yaml" }))
  end)

  it("returns nil for anything else", function()
    assert.is_nil(selector.params_to_uri(42))
    assert.is_nil(selector.params_to_uri({}))
  end)
end)

describe("selector.resolve", function()
  before_each(function()
    selector.reset()
    registry.reset()
  end)

  it("returns vim.NIL when nothing is registered", function()
    local bufnr, _, uri = make_buffer({ "a: 1" })
    local cfg = config.build({})
    assert.equals(vim.NIL, selector.resolve(cfg, uri, fake_client))
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)

  it("returns vim.NIL when the registered select returns nil", function()
    local bufnr, _, uri = make_buffer({ "a: 1" })
    registry.register({ name = "noop", select = function() end })
    local cfg = config.build({})
    assert.equals(vim.NIL, selector.resolve(cfg, uri, fake_client))
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)

  it("passes the selection through the alias table", function()
    local bufnr, _, uri = make_buffer({ "a: 1" })
    registry.register({
      name = "gh",
      select = function()
        return "gh"
      end,
    })
    local cfg = config.build({ schemas = { gh = "https://example.com/gh.json" } })
    assert.equals("https://example.com/gh.json", selector.resolve(cfg, uri, fake_client))
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)

  it("uses matcher+schema registrations", function()
    local bufnr, _, uri = make_buffer({ "a: 1" })
    registry.register({
      name = "gh",
      matcher = function(ctx)
        return ctx.path:match("%.yaml$") ~= nil
      end,
      schema = "https://example.com/gh.json",
    })
    local cfg = config.build({})
    assert.equals("https://example.com/gh.json", selector.resolve(cfg, uri, fake_client))
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)

  it("falls through to the next registration by priority when one opts out", function()
    local bufnr, _, uri = make_buffer({ "a: 1" })
    registry.register({
      name = "high",
      priority = 100,
      select = function()
        return nil
      end,
    })
    registry.register({
      name = "low",
      priority = 10,
      select = function()
        return "low-wins"
      end,
    })
    local cfg = config.build({ schemas = { ["low-wins"] = "https://example.com/low.json" } })
    assert.equals("https://example.com/low.json", selector.resolve(cfg, uri, fake_client))
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)

  it("merges schemas contributed via registrations with cfg.schemas winning on conflict", function()
    local bufnr, _, uri = make_buffer({ "a: 1" })
    registry.register({
      name = "contrib",
      schemas = { gh = "https://from-registry.example.com/gh.json" },
      select = function()
        return "gh"
      end,
    })
    local cfg = config.build({ schemas = { gh = "https://from-setup.example.com/gh.json" } })
    assert.equals("https://from-setup.example.com/gh.json", selector.resolve(cfg, uri, fake_client))
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)

  it("returns vim.NIL and notifies once when a select throws repeatedly", function()
    local bufnr, _, uri = make_buffer({ "a: 1" })
    local calls = 0
    local orig_notify = vim.notify
    vim.notify = function()
      calls = calls + 1
    end

    registry.register({
      name = "boom",
      select = function()
        error("boom")
      end,
    })
    local cfg = config.build({})
    assert.equals(vim.NIL, selector.resolve(cfg, uri, fake_client))
    assert.equals(vim.NIL, selector.resolve(cfg, uri, fake_client))

    vim.notify = orig_notify
    assert.equals(1, calls)
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)

  it("gives select a working ctx.path and ctx.root_dir", function()
    local bufnr, path, uri = make_buffer({ "a: 1" })
    local seen
    registry.register({
      name = "see",
      select = function(ctx)
        seen = ctx
        return nil
      end,
    })
    local cfg = config.build({})
    selector.resolve(cfg, uri, fake_client)
    assert.equals(path, seen.path)
    assert.equals("/root", seen.root_dir)
    assert.equals(bufnr, seen.bufnr)
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)

  if has_parser() then
    it("exposes the parsed document through ctx.yaml()", function()
      local bufnr, _, uri = make_buffer({ "kind: Service" })
      local seen
      registry.register({
        name = "see",
        select = function(ctx)
          seen = ctx.yaml()
          return nil
        end,
      })
      local cfg = config.build({})
      selector.resolve(cfg, uri, fake_client)
      assert.same({ kind = "Service" }, seen)
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("does not parse when ctx.yaml() is never called", function()
      local bufnr, _, uri = make_buffer({ "not: [valid: yaml: at: all" })
      registry.register({
        name = "noop",
        select = function()
          return nil
        end,
      })
      local cfg = config.build({})
      -- Would error while parsing if parsing happened eagerly; it must not.
      assert.equals(vim.NIL, selector.resolve(cfg, uri, fake_client))
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("returns nil for a buffer larger than max_parse_bytes", function()
      local bufnr, _, uri = make_buffer({ "a: 1" })
      local seen
      registry.register({
        name = "see",
        select = function(ctx)
          seen = ctx.yaml()
          return nil
        end,
      })
      local cfg = config.build({ max_parse_bytes = 1 })
      selector.resolve(cfg, uri, fake_client)
      assert.is_nil(seen)
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end
end)
