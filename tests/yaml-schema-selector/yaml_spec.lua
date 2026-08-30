local yaml = require("yaml-schema-selector.yaml")

local function has_parser()
  return pcall(vim.treesitter.get_string_parser, "a: b", "yaml")
end

if not has_parser() then
  -- Skip module entirely: no `yaml` treesitter parser is installed in this
  -- test environment (see tests/minimal_init.lua).
  describe("yaml.parse [skipped: no yaml treesitter parser]", function()
    it("is skipped", function() end)
  end)
  return
end

describe("yaml.parse", function()
  it("parses a nested block mapping", function()
    local docs = yaml.parse("a: 1\nb:\n  c: 2\n  d: 3\n")
    assert.same({ { a = 1, b = { c = 2, d = 3 } } }, docs)
  end)

  it("parses a block sequence", function()
    local docs = yaml.parse("items:\n  - one\n  - two\n")
    assert.same({ { items = { "one", "two" } } }, docs)
  end)

  it("parses a block sequence of mappings", function()
    local docs = yaml.parse("items:\n  - k: v\n  - k: w\n")
    assert.same({ { items = { { k = "v" }, { k = "w" } } } }, docs)
  end)

  it("parses flow sequences and mappings", function()
    local docs = yaml.parse("tags: [a, b]\nm: {x: 1, y: 2}\n")
    assert.same({ { tags = { "a", "b" }, m = { x = 1, y = 2 } } }, docs)
  end)

  it("converts scalar types", function()
    local docs = yaml.parse("i: 3\nf: 1.5\nt: true\nff: false\ns: hello\n")
    assert.same({ { i = 3, f = 1.5, t = true, ff = false, s = "hello" } }, docs)
  end)

  it("keeps colons inside quoted strings intact", function()
    local docs = yaml.parse('q: "x: y"\n')
    assert.same({ { q = "x: y" } }, docs)
  end)

  it("unescapes double-quoted scalars", function()
    local docs = yaml.parse('q: "a\\tb\\nc"\n')
    assert.same({ { q = "a\tb\nc" } }, docs)
  end)

  it("does not unescape single-quoted scalars, except doubled quotes", function()
    local docs = yaml.parse("q: 'a\\tb''c'\n")
    assert.same({ { q = "a\\tb'c" } }, docs)
  end)

  it("drops keys whose value is null or empty", function()
    local docs = yaml.parse("a: ~\nb: null\nc:\nd: 1\n")
    assert.same({ { d = 1 } }, docs)
  end)

  it("splits multi-document files on ---", function()
    local docs = yaml.parse("a: 1\n---\nb: 2\n")
    assert.same({ { a = 1 }, { b = 2 } }, docs)
  end)

  it("keeps the last value when a key is duplicated", function()
    local docs = yaml.parse("a: 1\na: 2\n")
    assert.same({ { a = 2 } }, docs)
  end)

  it("returns an empty list for an empty document", function()
    local docs = yaml.parse("")
    assert.same({}, docs)
  end)

  it("decodes a literal block scalar", function()
    local docs = yaml.parse("a: |\n  line1\n  line2\n")
    assert.same({ { a = "line1\nline2" } }, docs)
  end)

  it("decodes a folded block scalar", function()
    local docs = yaml.parse("a: >\n  line1\n  line2\n")
    assert.same({ { a = "line1 line2" } }, docs)
  end)
end)
