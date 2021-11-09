local has_telescope = pcall(require, 'telescope')

local pickers
local make_entry
local telescope_conf
local finders
local actions
local action_state
local themes

local function init_telescope()
  pickers = require('telescope.pickers')
  make_entry = require('telescope.make_entry')
  telescope_conf = require('telescope.config').values
  finders = require('telescope.finders')
  actions = require('telescope.actions')
  action_state = require('telescope.actions.state')
  themes = require('telescope.themes')
end

if has_telescope then init_telescope() end

local M = {
  conf = {},
  has_telescope = has_telescope,
  telescope = has_telescope and {
    themes = themes
  } or nil
}

M.setup_lib = function(conf)
  M.conf = vim.tbl_deep_extend('force', M.conf, conf)
  M.logger.debug('lib:', vim.inspect(M.conf))
end

local logger = {
  debug = function(...)
    if M.conf.debug then
      print("goto-preview:", ...)
    end
  end
}

M.logger = logger

local run_hook_function = function(buffer, new_window)
  local success, result = pcall(M.conf.post_open_hook, buffer, new_window)
  logger.debug("post_open_hook call success:", success, result)
end

function M.tablefind(tab,el)
  for index, value in pairs(tab) do
    if value == el then
      return index
    end
  end
end

M.remove_curr_win = function()
  local index = M.tablefind(M.windows, vim.api.nvim_get_current_win())
  if index then
    table.remove(M.windows, index)
  end
end

M.windows = {}

M.setup_aucmds = function()
  vim.cmd[[
    augroup goto-preview
      au!
      au WinClosed * lua require('goto-preview').remove_curr_win()
      au BufEnter * lua require('goto-preview').buffer_entered()
    augroup end
  ]]
end

local open_floating_win = function(target, position)
  local buffer = type(target) == 'string' and vim.uri_to_bufnr(target) or target
  local bufpos = { vim.fn.line(".")-1, vim.fn.col(".") } -- FOR relative='win'
  local zindex = vim.tbl_isempty(M.windows) and 1 or #M.windows+1
  local new_window = vim.api.nvim_open_win(buffer, true, {
    relative='win',
    width=M.conf.width,
    height=M.conf.height,
    border=M.conf.border,
    bufpos=bufpos,
    zindex=zindex,
    win=vim.api.nvim_get_current_win()
  })

  table.insert(M.windows, new_window)

  if M.conf.opacity then vim.api.nvim_win_set_option(new_window, "winblend", M.conf.opacity) end
  vim.api.nvim_buf_set_option(buffer, 'bufhidden', 'wipe')
  vim.api.nvim_win_set_var(new_window, "is-goto-preview-window", 1)

  logger.debug(vim.inspect({
    curr_window = vim.api.nvim_get_current_win(),
    new_window = new_window,
    bufpos = bufpos,
    get_config = vim.api.nvim_win_get_config(new_window),
    get_current_line = vim.api.nvim_get_current_line(),
    windows = M.windows
  }))

  run_hook_function(buffer, new_window)

  vim.api.nvim_win_set_cursor(new_window, position)
end
M.open_floating_win = open_floating_win

M.buffer_entered =  function()
  local curr_buf = vim.api.nvim_get_current_buf()
  local curr_win = vim.api.nvim_get_current_win()

  local success, result = pcall(vim.api.nvim_win_get_var, curr_win, 'is-goto-preview-window')

  if success and result == 1 then
    logger.debug('buffer_entered was called and will run hook function')
    run_hook_function(curr_buf, curr_win)
  end
end

local function open_references_previewer(prompt_title, items)
  if has_telescope then
    local opts = M.conf.references.telescope
    local entry_maker = make_entry.gen_from_quickfix(opts)
    local previewer = nil

    if not opts.hide_preview then
      previewer = telescope_conf.qflist_previewer(opts)
    end

    pickers.new(opts, {
      prompt_title = prompt_title,
      finder = finders.new_table {
        results = items,
        entry_maker = entry_maker,
      },
      previewer = previewer,
      sorter = telescope_conf.generic_sorter(opts),
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
  else
    error('goto_preview_references requires Telescope.nvim')
  end
end

local handle = function(result)
  if not result then return end

  local data = result[1] or result

  local target = nil
  local cursor_position = {}

  target, cursor_position = M.conf.lsp_configs.get_config(data)

  open_floating_win(target, cursor_position)
end

local handle_references = function(result)
  if not result then return end
  local items = {}

  vim.list_extend(items, vim.lsp.util.locations_to_items(result) or {})

  open_references_previewer('References', items)
end

local legacy_handler = function(lsp_call)
  return function(_, _, result)
    if lsp_call ~= nil and lsp_call == 'textDocument/references' then
      logger.debug('raw result', vim.inspect(result))
      handle_references(result)
    else
      handle(result)
    end
  end
end

local handler = function(lsp_call)
  return function(_, result, _, _)
    if lsp_call ~= nil and lsp_call == 'textDocument/references' then
      logger.debug('raw result', vim.inspect(result))
      handle_references(result)
    else
      handle(result)
    end
  end
end

M.get_handler = function(lsp_call)
  -- Only really need to check one of the handlers
  if debug.getinfo(vim.lsp.handlers['textDocument/definition']).nparams == 4 then
    logger.debug('calling new handler')
    return handler(lsp_call)
  else
    logger.debug('calling legacy handler')
    return legacy_handler(lsp_call)
  end
end

return M
