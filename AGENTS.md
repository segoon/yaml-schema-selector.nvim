## Core documentation

- @README.md - the main user documentation
- @doc/yaml-schema-selector.nvim.txt - the vim help file

## Quick Reference

**Language:** Lua. Neovim plugin. Minimum Neovim: 0.11.

**Layout:**
- `lua/yaml-schema-selector/` — all plugin logic (modules go here)
- `plugin/yaml_schema_selector.lua` — entry point, load guard + user command only; no logic
- `tests/yaml-schema-selector/` — mirrors `lua/yaml-schema-selector/` structure

**Conventions**
- stylua
- luacheck
- luacats annotations (**MANDATORY**)
- make test + make format + make lint

## Development

- Never call `git`, it is run manually by the user
- TDD
- DRY, KISS, SOLID
- The plugin is layer-only: it never starts or configures `yaml-language-server` itself, only
  attaches to an already-running client (see `lua/yaml-schema-selector/lsp.lua`)
- When fixing a bug, search for similar bugs in the nearby code
- When found a bug, elaborate whether it is possible to redesign the system to make such bugs
  impossible
- max *.lua file size = 600 lines

## Documentation

- `doc/yaml-schema-selector.nvim.txt` — the vim help file (`:help yaml-schema-selector.nvim`),
  hand-written (no generator in this repo)
- Any change that adds or changes commands, config options, or public API **must** update it and
  `README.md`

## User interaction

User experience is the priority.
Handle anything related to user interaction very carefully.
Examples:
- error messages (`vim.notify`, `:checkhealth`)
- documentation
- `setup()` and its validation
- user commands
