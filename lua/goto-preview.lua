local pickers = require('telescope.pickers')
local make_entry = require('telescope.make_entry')
local conf = require('telescope.config').values
local finders = require('telescope.finders')
local themes = require('telescope.themes')
local actions = require('telescope.actions')
local action_state = require('telescope.actions.state')

local M = {
  conf = {
    width = 120; -- Width of the floating window
    height = 15; -- Height of the floating window
    default_mappings = false; -- Bind default mappings
    debug = false; -- Print debug information
    opacity = nil; -- 0-100 opacity level of the floating window where 100 is fully transparent.
    lsp_configs = { -- Lsp result configs
      get_config = function(data)
        local uri = data.targetUri or data.uri
        local range = data.targetRange or data.range

        return uri, { range.start.line +1, range.start.character }
      end;
    };
    post_open_hook = nil -- A function taking two arguments, a buffer and a window to be ran as a hook.
  }
}

local logger = {
  debug = function(...)
    if M.conf.debug then
      print("goto-preview:", ...)
    end
  end
}

M.setup = function(conf)
  if conf and not vim.tbl_isempty(conf) then
    M.conf = vim.tbl_extend('force', M.conf, conf)

    if M.conf.default_mappings then
      M.apply_default_mappings()
    end
  end
end

local function tablefind(tab,el)
  for index, value in pairs(tab) do
    if value == el then
      return index
    end
  end
end

local windows = {}

local open_floating_win = function(target, position)
  local buffer = vim.uri_to_bufnr(target)
  local bufpos = { vim.fn.line(".")-1, vim.fn.col(".") } -- FOR relative='win'
  local zindex = vim.tbl_isempty(windows) and 1 or #windows+1
  local new_window = vim.api.nvim_open_win(buffer, true, {
    relative='win',
    width=M.conf.width,
    height=M.conf.height,
    border={"↖", "─" ,"┐", "│", "┘", "─", "└", "│"},
    bufpos=bufpos,
    zindex=zindex, -- TODO: do I need to set this at all?
    win=vim.api.nvim_get_current_win()
  })

  if M.conf.opacity then vim.api.nvim_win_set_option(new_window, "winblend", M.conf.opacity) end
  vim.api.nvim_buf_set_option(buffer, 'bufhidden', 'wipe')

  table.insert(windows, new_window)

  logger.debug(vim.inspect({
    windows = windows,
    curr_window = vim.api.nvim_get_current_win(),
    new_window = new_window,
    bufpos = bufpos,
    get_config = vim.api.nvim_win_get_config(new_window),
    get_current_line = vim.api.nvim_get_current_line()
  }))

  vim.cmd[[
    augroup close_float
      au!
      au WinClosed * lua require('goto-preview').remove_curr_win()
    augroup end
  ]]

  M.run_hook_function(buffer, new_window)

  print('==== new_window, position', vim.inspect(new_window), vim.inspect(position))
  vim.api.nvim_win_set_cursor(new_window, position)
end

M.run_hook_function = function(buffer, new_window)
  local success, result = pcall(M.conf.post_open_hook, buffer, new_window)
  logger.debug("post_open_hook call success:", success, result)
end

local function open_references_previewer(prompt_title, items, find_opts)
  local opts = themes.get_dropdown({hide_preview = false})
  local entry_maker = make_entry.gen_from_quickfix(opts)
  local previewer = nil
  if not find_opts.hide_preview then
    previewer = conf.qflist_previewer(opts)
  end

  pickers.new(opts, {
    prompt_title = prompt_title,
    finder = finders.new_table {
      results = items,
      entry_maker = entry_maker,
    },
    previewer = previewer,
    sorter = conf.generic_sorter(opts),
    attach_mappings = function(prompt_bufnr)
      actions.select_default:replace(function()
        local selection = action_state.get_selected_entry()
        actions.close(prompt_bufnr)

        local val = selection.value
        open_floating_win(vim.uri_from_fname(val.filename), { val.lnum, val.col })
      end)

      return true
    end,
  }):find()
end

local handle = function(result)
  if not result then return end

  local data = result[1]

  local target = nil
  local cursor_position = {}

  target, cursor_position = M.conf.lsp_configs.get_config(data)

  open_floating_win(target, cursor_position)
end

local handle_references = function(result)
  if not result then return end
  local items = {}

  vim.list_extend(items, vim.lsp.util.locations_to_items(result) or {})

  open_references_previewer('References', items, {})
end

local legacy_handler = function(lsp_call)
  return function(_, _, result)
    if lsp_call ~= nil and lsp_call == 'textDocument/references' then
      handle_references(result)
    else
      handle(result)
    end
  end
end

local handler = function(lsp_call)
  return function(_, result, _, _)
    if lsp_call ~= nil and lsp_call == 'textDocument/references' then
      handle_references(result)
    else
      handle(result)
    end
  end
end

local get_handler = function(lsp_call)
  -- Only really need to check one of the handlers
  if debug.getinfo(vim.lsp.handlers['textDocument/definition']).nparams == 4 then
    return handler(lsp_call)
  else
    return legacy_handler(lsp_call)
  end
end

local function print_lsp_error(lsp_call)
  print('goto-preview: Error calling LSP' + lsp_call + '. The current language lsp might not support it.')
end

M.lsp_request_definition = function()
  local params = vim.lsp.util.make_position_params()
  local lsp_call = "textDocument/definition"
  local success, _ = pcall(vim.lsp.buf_request, 0, lsp_call, params, get_handler())
  if not success then print_lsp_error(lsp_call) end
end

M.lsp_request_implementation = function()
  local params = vim.lsp.util.make_position_params()
  local lsp_call = "textDocument/implementation"
  local success, _ = pcall(vim.lsp.buf_request, 0, lsp_call, params, get_handler())
  if not success then print_lsp_error(lsp_call) end
end

M.lsp_request_references = function()
  local params = vim.lsp.util.make_position_params()
  local lsp_call = "textDocument/references"
  local success, _ = pcall(vim.lsp.buf_request, 0, lsp_call, params, get_handler(lsp_call))
  if not success then print_lsp_error(lsp_call) end
end

M.close_all_win = function()
  for index = #windows, 1, -1 do
    local window = windows[index]
    pcall(vim.api.nvim_win_close, window, true)
  end
end

M.remove_curr_win = function()
  local index = tablefind(windows, vim.api.nvim_get_current_win())
  if index then
    table.remove(windows, index)
  end
end

M.goto_preview_definition = M.lsp_request_definition
M.goto_preview_implementation = M.lsp_request_definition
M.goto_preview_references = M.lsp_request_references
-- Mappings

M.apply_default_mappings = function()
  local has_vimp, vimp = pcall(require, "vimp")
  if M.conf.default_mappings then
    -- if has_vimp then
    --   vimp.unmap_all()
    --   vimp.nnoremap('gpi', M.lsp_request(false))
    --   vimp.nnoremap('gpd', M.lsp_request(true))
    --   vimp.nnoremap('gP', M.close_all_win)

    --   -- Resize windows
    --   vimp.nnoremap('<left>', '<C-w><')
    --   vimp.nnoremap('<right>', '<C-w>>')
    --   vimp.nnoremap('<up>', '<C-w>-')
    --   vimp.nnoremap('<down>', '<C-w>+')
    -- else
    vim.api.nvim_set_keymap("n", "gpd", "<cmd>lua require('goto-preview').goto_preview_definition()<CR>", {noremap=true})
    vim.api.nvim_set_keymap("n", "gpi", "<cmd>lua require('goto-preview').goto_preview_implementation()<CR>", {noremap=true})
    vim.api.nvim_set_keymap("n", "gpr", "<cmd>lua require('goto-preview').goto_preview_references()<CR>", {noremap=true})
    vim.api.nvim_set_keymap("n", "gP", "<cmd>lua require('goto-preview').close_all_win()<CR>", {noremap=true})
    -- end
  end
end

return M

