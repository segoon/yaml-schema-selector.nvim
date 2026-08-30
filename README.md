# yaml-schema-selector.nvim

Pick the JSON Schema `yaml-language-server` uses for a buffer with a Lua
function, instead of static glob patterns.

`yaml-language-server` normally maps schemas to files with `yaml.schemas`
glob patterns, a modeline, or the SchemaStore catalog. That falls short when
the right schema depends on something a glob cannot express — the document's
own content, a repo-local convention, etc.

The server exposes an escape hatch for exactly this: register as its
**custom schema provider**, and it will ask you, per document, which schema
to use. This plugin is a thin layer over that hook: it does not start or
configure `yaml-language-server` itself, and just attaches to an already
running client.

## Requirements

- Neovim >= 0.11
- `yaml-language-server`, configured and started however you like (e.g. via
  `nvim-lspconfig`'s `yamlls`, or manually with `vim.lsp.enable`/`vim.lsp.start`)
- The `yaml` treesitter parser (`:TSInstall yaml`), only if you want to use
  `ctx.yaml()` in your selector

## Installation

With [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "segoon/yaml-schema-selector.nvim",
  ft = "yaml", -- lazy-load on yaml buffers; setup() only wires into yamlls via LspAttach
  opts = {
    -- equivalent to require("yaml-schema-selector").setup({ ... })
    schemas = {
      gh_workflow = "https://json.schemastore.org/github-workflow.json",
    },
    select = function(ctx)
      if ctx.path:match("/%.github/workflows/") then
        return "gh_workflow"
      end
      return nil -- fall back to modelines / yaml.schemas / SchemaStore
    end,
  },
},
```

## Setup

```lua
require("yaml-schema-selector").setup({
  server_name = "yamlls", -- name of the LSP client to layer onto (default)

  schemas = {
    gh_workflow = "https://json.schemastore.org/github-workflow.json",
    k8s = "kubernetes", -- the yaml-language-server's own k8s handling
    house = "./schemas/house.json", -- resolved relative to root_dir
  },

  select = function(ctx)
    -- Content-driven: works no matter where the file lives.
    local doc = ctx.yaml()
    if doc and doc.apiVersion and doc.kind then
      return "k8s"
    end

    -- Path-driven.
    if ctx.path:match("/%.github/workflows/") then
      return "gh_workflow"
    end

    -- nil: fall back to modelines / yaml.schemas / SchemaStore.
    return nil
  end,
})
```

`select` must be **synchronous** — it runs inside the handler for the
server's `custom/schema/request`, which cannot be answered asynchronously.

### `ctx` fields

| field | type | meaning |
|---|---|---|
| `uri` | `string` | document URI as sent by the server |
| `path` | `string` | absolute filesystem path |
| `filename` | `string` | basename of `path` |
| `bufnr` | `integer?` | buffer handle, or `nil` if not loaded |
| `filetype` | `string?` | buffer filetype, or `nil` if not loaded |
| `root_dir` | `string?` | root directory of the LSP client |
| `client_id` | `integer` | id of the `yamlls` client |
| `schemas` | `table<string,string>` | the configured alias table |
| `lines(n?)` | `fun(n?): string[]` | first `n` lines (default: all), lazy |
| `yaml()` | `fun(): table?` | first YAML document as a Lua value, lazy |
| `yaml_documents()` | `fun(): table[]` | all `---`-separated documents, lazy |

`select` may return `nil`, a single value, or a list of values. Each value is
either a key of `schemas`, a full URI, a filesystem path (absolute, `~`-
relative, or relative to `root_dir`), or the literal string `"kubernetes"`.

### `ctx.yaml()` limitations

`ctx.yaml()`/`ctx.yaml_documents()` parse the buffer with the `yaml`
treesitter grammar — no network calls, no external process, safe to call from
a synchronous handler. This is a lightweight parse, not a full YAML 1.2
implementation:

- A key whose value is null or empty (`foo:`, `foo: ~`, `foo: null`) is left
  out of the resulting table entirely, so `doc.foo and doc.foo.bar` guards
  work the way you'd expect.
- Anchors, aliases and merge keys (`<<:`) are not resolved.
- Parsing is skipped (and `ctx.yaml()` returns `nil`) for buffers larger than
  `max_parse_bytes` (default 1 MiB), and when the `yaml` parser isn't
  installed.

## Commands

- `:YamlSchemaRefresh` — ask the server to re-resolve the schema for every
  open document. Useful when something your `select` function depends on
  changed outside of Neovim.

## Lua API

- `require("yaml-schema-selector").setup(opts)`
- `require("yaml-schema-selector").refresh()`
- `require("yaml-schema-selector").resolve(bufnr?)` — run `select` for a
  buffer and return the normalized result, without going through the server;
  mainly useful for debugging (see also `:checkhealth yaml-schema-selector`).

## How it works

On `setup()`, and on every `LspAttach` of a client named `server_name`
(`yamlls` by default), the plugin:

1. installs a handler for the server's `custom/schema/request`;
2. sends the `yaml/registerCustomSchemaRequest` notification, which makes the
   server register the client as its schema provider;
3. sends `workspace/didChangeConfiguration`, so documents opened before
   registration get re-validated with the provider in the loop.

From then on, every time the server resolves a document's schema, it asks the
client (`custom/schema/request` with the document URI), and the answer wins
over `yaml.schemas`, the SchemaStore and `json/schemaAssociations` — though a
modeline or inline `$schema:` in the document still takes precedence over it.
