local status_cache = require("yaml-schema-selector.status_cache")

describe("status_cache", function()
  before_each(function()
    status_cache.reset()
  end)

  it("returns nil for a buffer that was never set", function()
    assert.is_nil(status_cache.get(123456))
  end)

  it("round-trips a set entry", function()
    local bufnr = vim.api.nvim_create_buf(false, true)
    local entry = { schema = "https://example.com/gh.json", source = "gh", uri = "file:///a.yaml", path = "/a.yaml" }
    status_cache.set(bufnr, entry)
    assert.same(entry, status_cache.get(bufnr))
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)

  it("clears the entry when the buffer is wiped out", function()
    local bufnr = vim.api.nvim_create_buf(false, true)
    status_cache.set(bufnr, { schema = "x", source = "s", uri = "file:///a.yaml", path = "/a.yaml" })
    vim.api.nvim_buf_delete(bufnr, { force = true })
    assert.is_nil(status_cache.get(bufnr))
  end)
end)
