local c35 = require("yaml-schema-selector.schemas.c35")

local function context(path)
  return {
    path = path,
    filename = vim.fs.basename(path),
    bufnr = nil,
  }
end

describe("c35 selector", function()
  local jobs
  local refreshes
  local notifications
  local cached_paths

  ---@param cache (fun(output: string): string)|nil
  local function set_dependencies(cache)
    c35.set_dependencies({
      fingerprint = function()
        return "fingerprint"
      end,
      generator = function()
        return "/plugin/generate-c35-cmy-schema.py"
      end,
      run = function(command, opts, callback)
        jobs[#jobs + 1] = { command = command, opts = opts, callback = callback }
      end,
      cache = cache,
      refresh = function()
        refreshes = refreshes + 1
      end,
      notify = function(message)
        notifications[#notifications + 1] = message
      end,
    })
  end

  before_each(function()
    jobs = {}
    refreshes = 0
    notifications = {}
    cached_paths = {}
    c35.reset()
    set_dependencies(function(output)
      return "file:///cache/" .. output .. ".json"
    end)
  end)

  after_each(function()
    for _, path in ipairs(cached_paths) do
      vim.fn.delete(path)
    end
    c35.reset()
  end)

  it("matches only codegen-module.yaml", function()
    assert.is_true(c35.matches(context("/arc/service/codegen-module.yaml")))
    assert.is_false(c35.matches(context("/arc/service/codegen-plugin.yaml")))
    assert.is_false(c35.matches(context("/arc/service/codegen-module.yml")))
  end)

  it("generates asynchronously and refreshes after caching the result", function()
    local ctx = context("/arc/service/codegen-module.yaml")
    assert.is_nil(c35.schema(ctx))
    assert.equals(1, #jobs)
    assert.same({ "ya", "tool", "tt", "python", "/plugin/generate-c35-cmy-schema.py", ctx.path }, jobs[1].command)
    assert.equals("/arc/service", jobs[1].opts.cwd)

    jobs[1].callback({ code = 0, stdout = "schema", stderr = "" })

    assert.equals(1, refreshes)
    assert.equals("file:///cache/schema.json", c35.schema(ctx))
    assert.equals(1, #jobs)
  end)

  it("caches canonical valid UTF-8 JSON", function()
    c35.reset()
    set_dependencies()

    local marker = vim.fn.tempname()
    local output = ('{\n  "description": "\\u041f\\u0440\\u0438\\u0432\\u0435\\u0442",\n  "marker": %s\n}\n'):format(
      vim.json.encode(marker)
    )
    local ctx = context("/arc/service/codegen-module.yaml")

    c35.schema(ctx)
    jobs[1].callback({ code = 0, stdout = output, stderr = "" })

    local uri = assert(c35.schema(ctx))
    local path = vim.uri_to_fname(uri)
    cached_paths[#cached_paths + 1] = path
    local bytes = vim.fn.readblob(path)

    assert.same({ description = "Привет", marker = marker }, vim.json.decode(bytes))
    assert.is_nil(bytes:find("\0", 1, true))
    assert.is_not_nil(bytes:find("Привет", 1, true))
    assert.equals(vim.fn.sha256(bytes) .. ".json", vim.fs.basename(path))
  end)

  it("does not start duplicate jobs for the same version", function()
    local ctx = context("/arc/service/codegen-module.yaml")
    c35.schema(ctx)
    c35.schema(ctx)
    assert.equals(1, #jobs)
  end)

  it("discards stale output and regenerates after a write", function()
    local ctx = context("/arc/service/codegen-module.yaml")
    c35.schema(ctx)
    c35.regenerate(ctx.path)
    assert.equals(1, #jobs)

    jobs[1].callback({ code = 0, stdout = "stale", stderr = "" })
    assert.equals(2, #jobs)
    assert.equals(0, refreshes)

    jobs[2].callback({ code = 0, stdout = "fresh", stderr = "" })
    assert.equals(1, refreshes)
    assert.equals("file:///cache/fresh.json", c35.schema(ctx))
  end)

  it("regenerates known modules after manual invalidation", function()
    local ctx = context("/arc/service/codegen-module.yaml")
    c35.schema(ctx)
    jobs[1].callback({ code = 0, stdout = "first", stderr = "" })

    c35.invalidate_all()
    assert.equals(2, #jobs)
    assert.is_nil(c35.schema(ctx))
  end)

  it("reports repeated generator failures only once and keeps no stale result", function()
    local ctx = context("/arc/service/codegen-module.yaml")
    c35.schema(ctx)
    jobs[1].callback({ code = 1, stdout = "", stderr = "broken\n" })
    assert.is_nil(c35.schema(ctx))
    assert.equals(1, #notifications)

    c35.regenerate(ctx.path)
    jobs[2].callback({ code = 1, stdout = "", stderr = "broken\n" })
    assert.equals(1, #notifications)
    assert.equals(0, refreshes)
  end)
end)
