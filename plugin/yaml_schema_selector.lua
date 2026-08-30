-- yaml-schema-selector.nvim entry point
-- This file is sourced automatically by Neovim's plugin loader.

-- Load guard: prevent double-loading.
if vim.g.loaded_yaml_schema_selector then
  return
end
vim.g.loaded_yaml_schema_selector = true

-- Require Neovim 0.11+ (client.handlers / vim.lsp.get_clients API used throughout).
if vim.fn.has("nvim-0.11") == 0 then
  vim.notify("yaml-schema-selector.nvim requires Neovim >= 0.11", vim.log.levels.ERROR)
  return
end

-- Explicit setup() call is required; nothing is activated here automatically.
-- Users must call require("yaml-schema-selector").setup({ select = ... }).

vim.api.nvim_create_user_command("YamlSchemaRefresh", function()
  require("yaml-schema-selector").refresh()
end, {
  desc = "Force yaml-language-server to re-resolve schemas for all open documents",
})
