local lib = require "goto-preview.lib"

local M = {
  conf = {
    width = 120, -- Width of the floating window
    height = 15, -- Height of the floating window
    border = { "↖", "─", "┐", "│", "┘", "─", "└", "│" }, -- Border characters of the floating window
    default_mappings = false, -- Bind default mappings
    resizing_mappings = false, -- Binds arrow keys to resizing the floating window.
    debug = false, -- Print debug information
    opacity = nil, -- 0-100 opacity level of the floating window where 100 is fully transparent.
    lsp_configs = {
      -- Lsp result configs
      get_config = function(data)
        lib.logger.debug("data from the lsp", vim.inspect(data))

        local uri = data.targetUri or data.uri
        local range = data.targetRange or data.range

        return uri, { range.start.line + 1, range.start.character }
      end,
    },
    post_open_hook = nil, -- A function taking two arguments, a buffer and a window to be ran as a hook.
    post_close_hook = nil, -- A function taking two arguments, a buffer and a window to be ran as a hook.
    references = {
      telescope = nil,
    },
    focus_on_open = true, -- Focus the floating window when opening it.
    dismiss_on_move = false, -- Dismiss the floating window when moving the cursor.
    force_close = true, -- passed into vim.api.nvim_win_close's second argument. See :h nvim_win_close
    bufhidden = "wipe", -- the bufhidden option to set on the floating window. See :h bufhidden
    stack_floating_preview_windows = true, -- Whether to nest floating windows
    same_file_float_preview = true, -- Whether to open a new floating window for a reference within the current file
    preview_window_title = { enable = true, position = "left" }, -- Whether to set the preview window title as the filename
  },
}

M.setup = function(conf)
  conf = conf or {}
  M.conf = vim.tbl_deep_extend("force", M.conf, conf)
  lib.logger.debug("non-lib:", vim.inspect(M.conf))
  lib.setup_lib(M.conf)
  lib.setup_aucmds()

  if M.conf.default_mappings then
    M.apply_default_mappings()
  end
  if M.conf.resizing_mappings then
    M.apply_resizing_mappings()
  end
end

local function print_lsp_error(lsp_call)
  print("goto-preview: Error calling LSP" + lsp_call + ". The current language lsp might not support it.")
end

--- Preview definition.
--- @param opts table: Custom config
---        • focus_on_open boolean: Focus the floating window when opening it.
---        • dismiss_on_move boolean: Dismiss the floating window when moving the cursor.
--- @see require("goto-preview").setup()
M.lsp_request_definition = function(opts)
  local params = vim.lsp.util.make_position_params()
  local lsp_call = "textDocument/definition"
  local success, _ = pcall(vim.lsp.buf_request, 0, lsp_call, params, lib.get_handler(lsp_call, opts))
  if not success then
    print_lsp_error(lsp_call)
  end
end

--- Preview type definition.
--- @param opts table: Custom config
---        • focus_on_open boolean: Focus the floating window when opening it.
---        • dismiss_on_move boolean: Dismiss the floating window when moving the cursor.
--- @see require("goto-preview").setup()
M.lsp_request_type_definition = function(opts)
  local params = vim.lsp.util.make_position_params()
  local lsp_call = "textDocument/typeDefinition"
  local success, _ = pcall(vim.lsp.buf_request, 0, lsp_call, params, lib.get_handler(lsp_call, opts))
  if not success then
    print_lsp_error(lsp_call)
  end
end

--- Preview implementation.
--- @param opts table: Custom config
---        • focus_on_open boolean: Focus the floating window when opening it.
---        • dismiss_on_move boolean: Dismiss the floating window when moving the cursor.
--- @see require("goto-preview").setup()
M.lsp_request_implementation = function(opts)
  local params = vim.lsp.util.make_position_params()
  local lsp_call = "textDocument/implementation"
  local success, _ = pcall(vim.lsp.buf_request, 0, lsp_call, params, lib.get_handler(lsp_call, opts))
  if not success then
    print_lsp_error(lsp_call)
  end
end

--- Preview declaration.
--- @param opts table: Custom config
---        • focus_on_open boolean: Focus the floating window when opening it.
---        • dismiss_on_move boolean: Dismiss the floating window when moving the cursor.
--- @see require("goto-preview").setup()
M.lsp_request_declaration = function(opts)
  local params = vim.lsp.util.make_position_params()
  local lsp_call = "textDocument/declaration"
  local success, _ = pcall(vim.lsp.buf_request, 0, lsp_call, params, lib.get_handler(lsp_call, opts))
  if not success then
    print_lsp_error(lsp_call)
  end
end

M.lsp_request_references = function(opts)
  local params = vim.lsp.util.make_position_params()

  lib.logger.debug("params pre manipulation", vim.inspect(params))
  if not params.context then
    params.context = {
      includeDeclaration = true,
    }
  end
  lib.logger.debug("params post manipulation", vim.inspect(params))

  local lsp_call = "textDocument/references"
  local success, _ = pcall(vim.lsp.buf_request, 0, lsp_call, params, lib.get_handler(lsp_call, opts))
  if not success then
    print_lsp_error(lsp_call)
  end
end

M.close_all_win = function(options)
  local windows = vim.api.nvim_tabpage_list_wins(0)

  for _, win in pairs(windows) do
    local index = lib.tablefind(lib.windows, win)
    table.remove(lib.windows, index)

    if options and options.skip_curr_window then
      if win ~= vim.api.nvim_get_current_win() then
        pcall(lib.close_if_is_goto_preview, win)
      end
    else
      pcall(lib.close_if_is_goto_preview, win)
    end
  end
end

M.remove_win = lib.remove_win
M.buffer_entered = lib.buffer_entered
M.buffer_left = lib.buffer_left
M.dismiss_preview = lib.dismiss_preview
M.goto_preview_definition = M.lsp_request_definition
M.goto_preview_type_definition = M.lsp_request_type_definition
M.goto_preview_implementation = M.lsp_request_implementation
M.goto_preview_declaration = M.lsp_request_declaration
M.goto_preview_references = M.lsp_request_references
-- Mappings

M.apply_default_mappings = function()
  if M.conf.default_mappings then
    vim.keymap.set("n", "gpd", require("goto-preview").goto_preview_definition, { desc = "Preview definition" })
    vim.keymap.set(
      "n",
      "gpt",
      require("goto-preview").goto_preview_type_definition,
      { desc = "Preview type definition" }
    )
    vim.keymap.set("n", "gpi", require("goto-preview").goto_preview_implementation, {
      desc = "Preview implementation",
    })
    vim.keymap.set("n", "gpD", require("goto-preview").goto_preview_declaration, {
      desc = "Preview declaration",
    })
    vim.keymap.set("n", "gpr", require("goto-preview").goto_preview_references, { desc = "Preview references" })
    vim.keymap.set("n", "gP", require("goto-preview").close_all_win, { desc = "Close preview windows" })
  end
end

M.apply_resizing_mappings = function()
  if M.conf.resizing_mappings then
    vim.keymap.set("n", "<left>", "<C-w><", { noremap = true })
    vim.keymap.set("n", "<right>", "<C-w>>", { noremap = true })
    vim.keymap.set("n", "<up>", "<C-w>-", { noremap = true })
    vim.keymap.set("n", "<down>", "<C-w>+", { noremap = true })
  end
end

return M
