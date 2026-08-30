-- Minimal Neovim init for the plenary.nvim test runner.
-- Used by: `make test` and CI.
--
-- This file is passed via `nvim -u tests/minimal_init.lua`.
-- It does NOT load the user's actual init.lua.

local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h:h")

-- Add the plugin itself to runtimepath
vim.opt.rtp:prepend(root)

-- Add plenary.nvim (cloned into .tests/ by `make deps` / CI)
local plenary_path = root .. "/.tests/plenary.nvim"
vim.opt.rtp:prepend(plenary_path)

-- Source plenary's plugin file so its runtime modules are available
vim.cmd("runtime plugin/plenary.vim")

-- Pick up an externally installed `yaml` treesitter parser (e.g. from
-- nvim-treesitter in the user's normal config), since this minimal init does
-- not manage one itself. Parsing tests are skipped when none is found.
for _, site in ipairs({ vim.fn.stdpath("data") .. "/site", "~/.local/share/nvim/site" }) do
  site = vim.fn.expand(site)
  if vim.fn.isdirectory(site .. "/parser") == 1 then
    vim.opt.rtp:append(site)
  end
end

-- Disable unnecessary providers to speed up startup
vim.g.loaded_node_provider = 0
vim.g.loaded_python3_provider = 0
vim.g.loaded_perl_provider = 0
vim.g.loaded_ruby_provider = 0
