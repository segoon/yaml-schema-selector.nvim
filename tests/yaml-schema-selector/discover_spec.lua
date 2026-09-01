local discover = require("yaml-schema-selector.discover")
local registry = require("yaml-schema-selector.registry")

---Create a temp dir on rtp with lua/yaml-schema-selector/schemas/<name> = content.
---@param files table<string, string> relative path (under schemas/) -> Lua source
---@return string dir
local function make_rtp_dir(files)
  local dir = vim.fn.tempname()
  local schemas_dir = dir .. "/lua/yaml-schema-selector/schemas"
  vim.fn.mkdir(schemas_dir, "p")
  for rel, content in pairs(files) do
    local path = schemas_dir .. "/" .. rel
    vim.fn.mkdir(vim.fs.dirname(path), "p")
    vim.fn.writefile(vim.split(content, "\n"), path)
  end
  vim.opt.rtp:append(dir)
  return dir
end

---@param dir string
local function remove_rtp_dir(dir)
  vim.opt.rtp:remove(dir)
  vim.fn.delete(dir, "rf")
end

describe("discover.discover", function()
  local dirs

  before_each(function()
    dirs = {}
    registry.reset()
    discover.reset()
  end)

  after_each(function()
    for _, dir in ipairs(dirs) do
      remove_rtp_dir(dir)
    end
    registry.reset()
    discover.reset()
  end)

  local function add(files)
    local dir = make_rtp_dir(files)
    dirs[#dirs + 1] = dir
    return dir
  end

  it("registers a single unnamed registration under a name derived from the path", function()
    add({
      ["kubernetes.lua"] = [[
        return { matcher = function() return true end, schema = "k8s" }
      ]],
    })
    discover.discover()
    assert.is_not_nil(registry.get("kubernetes"))
    assert.same({ kubernetes = true }, discover.discovered())
  end)

  it("derives a dotted name from a nested path", function()
    add({
      ["helm/values.lua"] = [[
        return { matcher = function() return true end, schema = "helm" }
      ]],
    })
    discover.discover()
    assert.is_not_nil(registry.get("helm.values"))
  end)

  it("suffixes unnamed entries in a list with #<index>", function()
    add({
      ["multi.lua"] = [[
        return {
          { matcher = function() return true end, schema = "a" },
          { matcher = function() return true end, schema = "b" },
        }
      ]],
    })
    discover.discover()
    assert.is_not_nil(registry.get("multi#1"))
    assert.is_not_nil(registry.get("multi#2"))
  end)

  it("keeps an explicit name and only suffixes the unnamed sibling", function()
    add({
      ["multi.lua"] = [[
        return {
          { name = "explicit", matcher = function() return true end, schema = "a" },
          { matcher = function() return true end, schema = "b" },
        }
      ]],
    })
    discover.discover()
    assert.is_not_nil(registry.get("explicit"))
    assert.is_not_nil(registry.get("multi#2"))
  end)

  it("does not let a file that errors on require block a sibling file", function()
    add({
      ["broken.lua"] = [[error("boom")]],
      ["good.lua"] = [[
        return { matcher = function() return true end, schema = "good" }
      ]],
    })
    discover.discover()
    assert.is_not_nil(registry.get("good"))
    local errs = discover.errors()
    assert.equals(1, #errs)
    assert.matches("boom", errs[1].err)
  end)

  it("records an error and registers nothing for a file returning nil", function()
    add({
      ["nothing.lua"] = [[return nil]],
    })
    discover.discover()
    assert.same({}, discover.discovered())
    assert.equals(1, #discover.errors())
  end)

  it("records an error and continues past a spec that fails registry validation", function()
    add({
      ["bad.lua"] = [[
        return { matcher = function() return true end }
      ]],
      ["good.lua"] = [[
        return { matcher = function() return true end, schema = "good" }
      ]],
    })
    discover.discover()
    assert.is_not_nil(registry.get("good"))
    assert.equals(1, #discover.errors())
  end)

  it("unregisters a name whose source file has since disappeared", function()
    local dir = add({
      ["gone.lua"] = [[
        return { matcher = function() return true end, schema = "gone" }
      ]],
    })
    discover.discover()
    assert.is_not_nil(registry.get("gone"))

    remove_rtp_dir(dir)
    dirs = {}

    discover.discover()
    assert.is_nil(registry.get("gone"))
    assert.same({}, discover.discovered())
  end)

  it("preserves a manual registration that reused a since-vanished discovered name", function()
    local dir = add({
      ["shared.lua"] = [[
        return { matcher = function() return true end, schema = "a" }
      ]],
    })
    discover.discover()
    assert.is_not_nil(registry.get("shared"))

    remove_rtp_dir(dir)
    dirs = {}
    registry.register({
      name = "shared",
      matcher = function()
        return true
      end,
      schema = "b",
    })

    discover.discover()
    assert.is_not_nil(registry.get("shared"))
    assert.equals("b", registry.get("shared").schema)
  end)

  it("discovered() reflects only the last run, not a cumulative history", function()
    add({
      ["one.lua"] = [[
        return { matcher = function() return true end, schema = "one" }
      ]],
    })
    discover.discover()
    assert.same({ one = true }, discover.discovered())

    add({
      ["two.lua"] = [[
        return { matcher = function() return true end, schema = "two" }
      ]],
    })
    discover.discover()
    assert.same({ one = true, two = true }, discover.discovered())
  end)

  it("records a duplicate-path error and keeps the first when two rtp entries collide", function()
    add({
      ["dup.lua"] = [[
        return { matcher = function() return true end, schema = "first" }
      ]],
    })
    add({
      ["dup.lua"] = [[
        return { matcher = function() return true end, schema = "second" }
      ]],
    })
    discover.discover()
    assert.is_not_nil(registry.get("dup"))
    assert.equals("first", registry.get("dup").schema)
    local errs = discover.errors()
    assert.equals(1, #errs)
    assert.matches("duplicate", errs[1].err)
  end)
end)

describe("yaml-schema-selector.discover", function()
  local dirs

  before_each(function()
    dirs = {}
    registry.reset()
    discover.reset()
  end)

  after_each(function()
    for _, dir in ipairs(dirs) do
      remove_rtp_dir(dir)
    end
    registry.reset()
    discover.reset()
  end)

  it("delegates to discover.discover()", function()
    local dir = make_rtp_dir({
      ["direct.lua"] = [[
        return { matcher = function() return true end, schema = "direct" }
      ]],
    })
    dirs[#dirs + 1] = dir
    require("yaml-schema-selector").discover()
    assert.is_not_nil(registry.get("direct"))
  end)
end)
