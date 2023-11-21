local M = {
  conf = {},
}

M.setup_lib = function(conf)
  M.conf = vim.tbl_deep_extend("force", M.conf, conf)
  M.logger.debug("lib:", vim.inspect(M.conf))
end

local function is_floating(window_id)
  return vim.api.nvim_win_get_config(window_id).relative ~= ""
end

local function is_curr_buf(buffer)
  return vim.api.nvim_get_current_buf() == buffer
end

local logger = {
  debug = function(...)
    if M.conf.debug then
      print("goto-preview:", ...)
    end
  end,
}

M.logger = logger

local run_post_open_hook_function = function(buffer, new_window)
  local success, result = pcall(M.conf.post_open_hook, buffer, new_window)
  logger.debug("post_open_hook call success:", success, result)
end

local run_post_close_hook_function = function(buffer, new_window)
  local success, result = pcall(M.conf.post_close_hook, buffer, new_window)
  logger.debug("post_close_hook call success:", success, result)
end

function M.tablefind(tab, el)
  for index, value in pairs(tab) do
    if value == el then
      return index
    end
  end
end

M.remove_win = function(win)
  local curr_buf = vim.api.nvim_get_current_buf()
  local curr_win = vim.api.nvim_get_current_win()

  local success, result = pcall(vim.api.nvim_win_get_var, curr_win, "is-goto-preview-window")

  if success and result == 1 then
    run_post_close_hook_function(curr_buf, curr_win)
  end

  local index = M.tablefind(M.windows, win or vim.api.nvim_get_current_win())
  if index then
    table.remove(M.windows, index)
  end
end

M.windows = {}

M.setup_aucmds = function()
  vim.cmd [[
    augroup goto-preview
      au!
      au WinClosed * lua require('goto-preview').remove_win()
      au BufEnter * lua require('goto-preview').buffer_entered()
      au BufLeave * lua require('goto-preview').buffer_left()
    augroup end
  ]]
end

M.dismiss_preview = function(winnr)
  logger.debug("dismiss_preview", winnr)
  if winnr then
    logger.debug("attempting to close ", winnr)
    pcall(vim.api.nvim_win_close, winnr, true)
  else
    logger.debug "attempting to all preview windows"
    for _, win in ipairs(M.windows) do
      M.close_if_is_goto_preview(win)
    end
  end
end

M.close_if_is_goto_preview = function(win_handle)
  local curr_buf = vim.api.nvim_get_current_buf()
  local curr_win = vim.api.nvim_get_current_win()

  local success, result = pcall(vim.api.nvim_win_get_var, win_handle, "is-goto-preview-window")
  if success and result == 1 then

    run_post_close_hook_function(curr_buf, curr_win)
    vim.api.nvim_win_close(win_handle, M.conf.force_close)
  end
end

local function set_title(buffer)
  if vim.fn.has "nvim-0.9.0" == 0 then
    logger.debug "title not supported in this version of neovim"
    return nil
  end

  local rel_filepath = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(buffer), ":.")
  return M.conf.preview_window_title.enable and rel_filepath or nil
end

local function set_title_pos()
  if vim.fn.has "nvim-0.9.0" == 0 then
    logger.debug "title_pos not supported in this version of neovim"
    return nil
  end

  return M.conf.preview_window_title.enable and M.conf.preview_window_title.position or nil
end

local function create_preview_win(buffer, bufpos, zindex, opts)
  local enter = function()
    return opts.focus_on_open or M.conf.focus_on_open or false
  end

  local stack_floating_preview_windows = function()
    return opts.stack_floating_preview_windows or M.conf.stack_floating_preview_windows or false
  end

  local same_file_float_preview = function()
    return opts.same_file_float_preview or M.conf.same_file_float_preview or false
  end

  logger.debug("focus_on_open", enter())
  logger.debug("stack_floating_preview_windows", stack_floating_preview_windows())

  local preview_window
  local curr_win = vim.api.nvim_get_current_win()
  local success, result = pcall(vim.api.nvim_win_get_var, curr_win, "is-goto-preview-window")

  if is_curr_buf(buffer) and not same_file_float_preview() then
    return curr_win
  end

  if not stack_floating_preview_windows() and is_floating(curr_win) and success and result == 1 then
    preview_window = curr_win
    vim.api.nvim_win_set_config(preview_window, {
      width = M.conf.width,
      height = M.conf.height,
      border = M.conf.border,
    })
    vim.api.nvim_win_set_buf(preview_window, buffer)
  else
    preview_window = vim.api.nvim_open_win(buffer, enter(), {
      relative = "win",
      width = M.conf.width,
      height = M.conf.height,
      border = M.conf.border,
      bufpos = bufpos,
      zindex = zindex,
      win = vim.api.nvim_get_current_win(),
      title = set_title(buffer),
      title_pos = set_title_pos(),
    })

    table.insert(M.windows, preview_window)
  end

  return preview_window
end

M.open_floating_win = function(target, position, opts)
  local buffer = type(target) == "string" and vim.uri_to_bufnr(target) or target
  local bufpos = { vim.fn.line(".") - 1, vim.fn.col(".") } -- FOR relative='win'
  local zindex = vim.tbl_isempty(M.windows) and 1 or #M.windows + 1

  opts = opts or {}

  local preview_window = create_preview_win(buffer, bufpos, zindex, opts)

  if M.conf.opacity then
    vim.api.nvim_win_set_option(preview_window, "winblend", M.conf.opacity)
  end
  if not is_curr_buf(buffer) then
    vim.api.nvim_buf_set_option(buffer, "bufhidden", M.conf.bufhidden)
  end
  vim.api.nvim_win_set_var(preview_window, "is-goto-preview-window", 1)

  logger.debug(vim.inspect {
    curr_window = vim.api.nvim_get_current_win(),
    preview_window = preview_window,
    bufpos = bufpos,
    get_config = vim.api.nvim_win_get_config(preview_window),
    get_current_line = vim.api.nvim_get_current_line(),
    windows = M.windows,
  })

  local dismiss = function()
    if opts.dismiss_on_move ~= nil then
      return opts.dismiss_on_move
    else
      return M.conf.dismiss_on_move
    end
  end

  logger.debug("dismiss_on_move", dismiss())
  if dismiss() then
    vim.api.nvim_command(
      string.format(
        "autocmd CursorMoved <buffer> ++once lua require('goto-preview').dismiss_preview(%d)",
        preview_window
      )
    )
  end

  -- Set position of the preview buffer equal to the target position so that correct preview position shows
  vim.api.nvim_win_set_cursor(preview_window, position)

  run_post_open_hook_function(buffer, preview_window)
end

M.buffer_entered = function()
  local curr_buf = vim.api.nvim_get_current_buf()
  local curr_win = vim.api.nvim_get_current_win()

  local success, result = pcall(vim.api.nvim_win_get_var, curr_win, "is-goto-preview-window")

  if success and result == 1 then
    logger.debug "buffer_entered was called and will run hook function"
    run_post_open_hook_function(curr_buf, curr_win)
  end
end

M.buffer_left = function()
  local curr_buf = vim.api.nvim_get_current_buf()
  local curr_win = vim.api.nvim_get_current_win()

  local success, result = pcall(vim.api.nvim_win_get_var, curr_win, "is-goto-preview-window")

  if success and result == 1 then
    logger.debug "buffer_left was called and will run hook function"
    run_post_close_hook_function(curr_buf, curr_win)
  end
end

local function _open_references_window(val)
  M.open_floating_win(vim.uri_from_fname(val.filename), { val.lnum, val.col })
end

local function open_references_previewer(prompt_title, items)
  local has_telescope, _ = pcall(require, "telescope")

  if has_telescope then
    local pickers = require "telescope.pickers"
    local make_entry = require "telescope.make_entry"
    local telescope_conf = require("telescope.config").values
    local finders = require "telescope.finders"
    local actions = require "telescope.actions"
    local action_state = require "telescope.actions.state"
    local themes = require "telescope.themes"

    local opts = M.conf.references.telescope or themes.get_dropdown { hide_preview = false }
    local entry_maker = make_entry.gen_from_quickfix(opts)
    local previewer = nil

    if not opts.hide_preview then
      previewer = telescope_conf.qflist_previewer(opts)
    end

    if #items == 1 then
      _open_references_window(items[1])
    else
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

            _open_references_window(selection.value)
          end)

          return true
        end,
      }):find()
    end
  else
    error "goto_preview_references requires Telescope.nvim"
  end
end

local handle = function(result, opts)
  if not result then
    return
  end

  local data = result[1] or result

  local target = nil
  local cursor_position = {}

  if vim.tbl_isempty(data) then
    logger.debug "The LSP returned no results. No preview to display."
    return
  end

  target, cursor_position = M.conf.lsp_configs.get_config(data)

  -- opts: focus_on_open, dismiss_on_move, etc.
  M.open_floating_win(target, cursor_position, opts)
end

local handle_references = function(result)
  if not result then
    return
  end
  local items = {}

  vim.list_extend(items, vim.lsp.util.locations_to_items(result, "utf-8") or {})

  open_references_previewer("References", items)
end

local legacy_handler = function(lsp_call, opts)
  return function(_, _, result)
    if lsp_call ~= nil and lsp_call == "textDocument/references" then
      logger.debug("raw result", vim.inspect(result))
      handle_references(result)
    else
      handle(result, opts)
    end
  end
end

local handler = function(lsp_call, opts)
  return function(_, result, _, _)
    if lsp_call ~= nil and lsp_call == "textDocument/references" then
      logger.debug("raw result", vim.inspect(result))
      handle_references(result)
    else
      handle(result, opts)
    end
  end
end

M.get_handler = function(lsp_call, opts)
  -- Only really need to check one of the handlers
  if debug.getinfo(vim.lsp.handlers["textDocument/definition"]).nparams == 4 then
    logger.debug "calling new handler"
    return handler(lsp_call, opts)
  else
    logger.debug "calling legacy handler"
    return legacy_handler(lsp_call, opts)
  end
end

return M
