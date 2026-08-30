local client = vim.lsp.get_clients({ bufnr = 0, name = "yamlls" })[1]
if client then
  client:request("yaml/get/jsonSchema", vim.uri_from_bufnr(0), function(err, result)
    print(vim.inspect(result))
  end, 0)
end
