-- Converts a YAML document into plain Lua values using the `yaml` treesitter
-- grammar. Only what a schema selector realistically needs is supported; see
-- the limitations listed in the README.

local M = {}

---Nodes that merely wrap a value and carry no information themselves.
---@type table<string, true>
local WRAPPER = {
  document = true,
  block_node = true,
  flow_node = true,
  block_sequence_item = true,
  plain_scalar = true,
}

---Nodes attached to a value that are not the value itself.
---@type table<string, true>
local DECORATION = {
  anchor = true,
  tag = true,
  comment = true,
}

---Single-character escapes recognised inside double-quoted scalars.
---@type table<string, string>
local ESCAPES = {
  ["0"] = "\0",
  a = "\a",
  b = "\b",
  t = "\t",
  ["\t"] = "\t",
  n = "\n",
  v = "\v",
  f = "\f",
  r = "\r",
  e = "\27",
  [" "] = " ",
  ['"'] = '"',
  ["/"] = "/",
  ["\\"] = "\\",
}

---@param node TSNode
---@param src string
---@return string
local function text(node, src)
  return vim.treesitter.get_node_text(node, src)
end

---Expand the escape sequences of a double-quoted scalar body.
---@param body string
---@return string
local function unescape(body)
  local out = {}
  local i = 1
  while i <= #body do
    local ch = body:sub(i, i)
    if ch ~= "\\" or i == #body then
      out[#out + 1] = ch
      i = i + 1
    else
      local nxt = body:sub(i + 1, i + 1)
      if nxt == "x" or nxt == "u" or nxt == "U" then
        local width = (nxt == "x" and 2) or (nxt == "u" and 4) or 8
        local digits = body:sub(i + 2, i + 1 + width)
        local code = #digits == width and tonumber(digits, 16) or nil
        if code then
          out[#out + 1] = vim.fn.nr2char(code)
          i = i + 2 + width
        else
          out[#out + 1] = nxt
          i = i + 2
        end
      else
        out[#out + 1] = ESCAPES[nxt] or nxt
        i = i + 2
      end
    end
  end
  return table.concat(out)
end

---Decode a block scalar, including its `|`/`>` header, indentation and chomping.
---@param raw string Full node text, starting with the header line.
---@return string
local function block_scalar(raw)
  local header, body = raw:match("^([^\n]*)\n(.*)$")
  if not header then
    return ""
  end

  local folded = header:sub(1, 1) == ">"
  local chomp = header:match("[-+]")

  local lines = vim.split(body, "\n")
  local indent = math.huge
  for _, line in ipairs(lines) do
    if line:match("%S") then
      indent = math.min(indent, #line:match("^%s*"))
    end
  end
  if indent == math.huge then
    indent = 0
  end
  for i, line in ipairs(lines) do
    lines[i] = line:sub(indent + 1)
  end

  local result = table.concat(lines, folded and " " or "\n")
  if chomp ~= "+" then
    result = result:gsub("%s+$", "")
  end
  return result
end

---Convert a scalar node to the matching Lua value.
---@param node TSNode
---@param src string
---@return string|number|boolean|nil
local function scalar_value(node, src)
  local kind = node:type()
  local raw = text(node, src)

  if kind == "integer_scalar" or kind == "float_scalar" then
    return tonumber(raw) or raw
  elseif kind == "boolean_scalar" then
    return raw:lower() == "true" or raw:lower() == "y" or raw:lower() == "yes" or raw:lower() == "on"
  elseif kind == "null_scalar" then
    return nil
  elseif kind == "single_quote_scalar" then
    return raw:sub(2, -2):gsub("''", "'")
  elseif kind == "double_quote_scalar" then
    return unescape(raw:sub(2, -2))
  elseif kind == "block_scalar" then
    return block_scalar(raw)
  end

  return raw
end

local convert

---Unwrap decoration-only wrappers down to the node carrying the actual value.
---@param node TSNode
---@return TSNode|nil
local function unwrap(node)
  while WRAPPER[node:type()] do
    local inner = nil
    for child in node:iter_children() do
      if child:named() and not DECORATION[child:type()] then
        inner = child
      end
    end
    if not inner then
      return nil
    end
    node = inner
  end
  return node
end

---Build a Lua table from a mapping node.
---@param node TSNode
---@param src string
---@return table
local function convert_mapping(node, src)
  local out = {}
  for child in node:iter_children() do
    local kind = child:type()
    if kind == "block_mapping_pair" or kind == "flow_pair" then
      local key_node = child:field("key")[1]
      local value_node = child:field("value")[1]
      if key_node then
        local key = convert(key_node, src)
        -- A pair without a value (`foo:`) leaves the key out entirely, so that
        -- `doc.foo and doc.foo.bar` guards behave the way users expect.
        if key ~= nil and value_node then
          out[key] = convert(value_node, src)
        end
      end
    end
  end
  return out
end

---Build a Lua array from a sequence node.
---@param node TSNode
---@param src string
---@return table
local function convert_sequence(node, src)
  local out = {}
  for child in node:iter_children() do
    if child:named() and not DECORATION[child:type()] then
      local value = convert(child, src)
      if value ~= nil then
        out[#out + 1] = value
      end
    end
  end
  return out
end

---Convert any node to its Lua representation.
---@param node TSNode
---@param src string
---@return any
convert = function(node, src)
  local inner = unwrap(node)
  if not inner then
    return nil
  end

  local kind = inner:type()
  if kind == "block_mapping" or kind == "flow_mapping" then
    return convert_mapping(inner, src)
  elseif kind == "block_sequence" or kind == "flow_sequence" then
    return convert_sequence(inner, src)
  end

  return scalar_value(inner, src)
end

---Convert every `document` node of an already-parsed tree.
---@param root TSNode Root node of a `yaml` tree.
---@param src string Source the tree was parsed from.
---@return table[] documents One entry per non-empty document.
function M.from_tree(root, src)
  local documents = {}
  for child in root:iter_children() do
    if child:type() == "document" then
      -- Empty documents are dropped rather than stored as a hole: Lua arrays
      -- cannot hold nil, and a sentinel would only trip users up.
      local value = convert(child, src)
      if value ~= nil then
        documents[#documents + 1] = value
      end
    end
  end
  return documents
end

---Parse a YAML string into a list of Lua values, one per `---` document.
---Returns an empty list when the `yaml` treesitter parser is unavailable.
---@param src string
---@return table[]
function M.parse(src)
  local ok, parser = pcall(vim.treesitter.get_string_parser, src, "yaml")
  if not ok or not parser then
    return {}
  end
  local tree = parser:parse()[1]
  if not tree then
    return {}
  end
  return M.from_tree(tree:root(), src)
end

return M
