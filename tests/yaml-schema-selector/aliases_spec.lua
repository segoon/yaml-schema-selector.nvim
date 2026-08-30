local aliases = require("yaml-schema-selector.aliases")

describe("aliases.resolve_one", function()
  local schemas = {
    gh = "https://json.schemastore.org/github-workflow.json",
    k8s = "kubernetes",
    rel = "schemas/house.json",
  }

  it("substitutes a known alias", function()
    assert.equals("https://json.schemastore.org/github-workflow.json", aliases.resolve_one("gh", schemas, "/root"))
  end)

  it("passes http(s) URIs through unchanged", function()
    assert.equals("https://example.com/s.json", aliases.resolve_one("https://example.com/s.json", schemas, "/root"))
  end)

  it("passes the kubernetes keyword through unchanged", function()
    assert.equals("kubernetes", aliases.resolve_one("kubernetes", schemas, "/root"))
  end)

  it("substitutes an alias pointing at the kubernetes keyword", function()
    assert.equals("kubernetes", aliases.resolve_one("k8s", schemas, "/root"))
  end)

  it("resolves a relative path against base_dir into a file URI", function()
    assert.equals("file:///root/pattern.json", aliases.resolve_one("pattern.json", {}, "/root"))
  end)

  it("resolves an absolute path into a file URI", function()
    assert.equals("file:///abs/schema.json", aliases.resolve_one("/abs/schema.json", {}, "/root"))
  end)

  it("expands ~ before treating the value as a path", function()
    local home = vim.fn.expand("~")
    assert.equals("file://" .. home .. "/s.json", aliases.resolve_one("~/s.json", {}, "/root"))
  end)

  it("substitutes an alias exactly once (no cycles)", function()
    local cyclic = { a = "b", b = "a" }
    -- "a" resolves to "b" and stops there: "b" is treated as a relative path,
    -- not looked up again in the alias table.
    assert.equals("file:///root/b", aliases.resolve_one("a", cyclic, "/root"))
  end)
end)

describe("aliases.valid_target", function()
  it("accepts a bare path", function()
    assert.is_true(aliases.valid_target("schemas/house.json"))
  end)

  it("accepts the kubernetes keyword", function()
    assert.is_true(aliases.valid_target("kubernetes"))
  end)

  it("accepts a well-formed https URI", function()
    assert.is_true(aliases.valid_target("https://example.com/s.json"))
  end)

  it("accepts a file URI with an empty authority", function()
    assert.is_true(aliases.valid_target("file:///abs/schema.json"))
  end)

  it("rejects a scheme with nothing after it", function()
    local ok, err = aliases.valid_target("https://")
    assert.is_false(ok)
    assert.is_string(err)
  end)

  it("rejects a scheme followed only by slashes", function()
    local ok = aliases.valid_target("https:///")
    assert.is_false(ok)
  end)
end)

describe("aliases.normalize", function()
  local schemas = { gh = "https://example.com/gh.json" }

  it("returns vim.NIL for nil", function()
    assert.equals(vim.NIL, aliases.normalize(nil, schemas, "/root"))
  end)

  it("returns vim.NIL for an empty list", function()
    assert.equals(vim.NIL, aliases.normalize({}, schemas, "/root"))
  end)

  it("resolves a single string", function()
    assert.equals("https://example.com/gh.json", aliases.normalize("gh", schemas, "/root"))
  end)

  it("resolves each entry of a list", function()
    local result = aliases.normalize({ "gh", "kubernetes" }, schemas, "/root")
    assert.same({ "https://example.com/gh.json", "kubernetes" }, result)
  end)
end)
