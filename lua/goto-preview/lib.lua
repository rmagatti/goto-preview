---@diagnostic disable: lowercase-global
local M = {
  conf = {},
}

logger = nil

-- Simple logger implementation for fallback
local function create_simple_logger(options)
  local log_level = options and options.log_level or "info"
  local prefix = options and options.prefix or ""
  local levels = { debug = 1, info = 2, warn = 3, error = 4 }
  local current_level = levels[log_level] or 2

  local function log(level, ...)
    if levels[level] >= current_level then
      local args = { ... }
      local msg = ""
      ---@diagnostic disable-next-line: unused-local
      for i, v in ipairs(args) do
        msg = msg .. tostring(v) .. " "
      end
      print(string.format("[%s][FALLBACK LOGGER - missing logger.nvim dependency] %s: %s", prefix, level:upper(), msg))
    end
  end

  return {
    debug = function(...) log("debug", ...) end,
    info = function(...) log("info", ...) end,
    warn = function(...) log("warn", ...) end,
    error = function(...) log("error", ...) end,
    new = function(opts) return create_simple_logger(opts) end
  }
end

M.setup_lib = function(conf)
  M.conf = vim.tbl_deep_extend("force", M.conf, conf)

  -- Try to require the logger module, fall back to simple implementation if not available
  local ok, logger_module = pcall(require, "logger")
  if ok then
    logger = logger_module:new({ log_level = M.conf.debug and "debug" or "info", prefix = "goto-preview" })
  else
    -- Use the simple logger implementation
    logger = create_simple_logger({ log_level = M.conf.debug and "debug" or "info", prefix = "goto-preview" })
  end

  M.logger = logger
  logger.debug("lib:", vim.inspect(M.conf))
end

local function is_floating(window_id)
  return vim.api.nvim_win_get_config(window_id).relative ~= ""
end

local function is_curr_buf(buffer)
  return vim.api.nvim_get_current_buf() == buffer
end


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

--- Setup the custom UI input functionality
M.setup_custom_input = function()
  -- Store the original vim.ui.input
  M._original_input = vim.ui.input

  -- Replace with our custom implementation
  vim.ui.input = function(opts, on_confirm)
    -- Create a new buffer for the input field
    local buf = vim.api.nvim_create_buf(false, true)

    -- Pre-populate with default text if provided
    local initial_text = opts.default or ""
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { initial_text })

    -- Calculate appropriate width based on content + padding
    local content_width = #initial_text
    local min_width = 20  -- Minimum width for small inputs
    local max_width = 120 -- Maximum width to prevent too wide windows
    local padding = 16    -- Extra space for cursor, line numbers, and comfort
    local width = math.min(max_width, math.max(min_width, content_width + padding))

    -- Open the floating window using our existing function
    local win = M.open_floating_win(buf, { 1, 0 }, {
      focus_on_open = true,
      dismiss_on_move = false,
      -- Override some settings specific to input windows
      same_file_float_preview = true,
      width = width,
      height = 1 -- Only one line for input
    })

    -- Move cursor to the end of any default text
    vim.api.nvim_win_set_cursor(win, { 1, #initial_text })

    -- Set window title if we have a prompt
    if vim.fn.has("nvim-0.9.0") == 1 and opts.prompt then
      vim.api.nvim_win_set_config(win, {
        title = opts.prompt,
        title_pos = "left"
      })
    end

    -- Function to handle result and clean up
    local function handle_result(result)
      -- Remove from windows table
      local index = M.tablefind(M.windows, win)
      if index then
        table.remove(M.windows, index)
      end

      -- Run post close hook if defined
      if M.conf.post_close_hook then
        run_post_close_hook_function(buf, win)
      end

      -- Close the window
      pcall(vim.api.nvim_win_close, win, true)

      -- Call the callback
      if on_confirm then
        on_confirm(result)
      end
    end

    -- Set keymaps for the input window
    local keymaps = {
      -- Normal mode mappings
      n = {
        ["<CR>"] = function()
          local result = vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1]
          handle_result(result)
        end,
        ["<Esc>"] = function()
          handle_result(nil)
        end,
        ["i"] = function()
          vim.cmd("startinsert")
        end,
        ["a"] = function()
          vim.cmd("startinsert")
        end,
      },

      -- Insert mode mappings
      i = {
        ["<CR>"] = function()
          local result = vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1]
          handle_result(result)
        end,
      },
    }

    -- Apply all keymaps
    for mode, maps in pairs(keymaps) do
      for key, func in pairs(maps) do
        vim.keymap.set(mode, key, func, { buffer = buf, nowait = true })
      end
    end

    -- Start in normal mode by default
    vim.cmd("stopinsert")
    vim.notify("Press <CR> to confirm, <Esc> to cancel", "info")
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
    -- Focus the previous preview if there is one
    if index > 1 then
      local prev_win = M.windows[index - 1]
      vim.api.nvim_set_current_win(prev_win)
    end
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
  logger.debug("width" .. vim.inspect(opts.width or M.conf.width), "info")
  logger.debug("height" .. vim.inspect(opts.height or M.conf.height), "info")

  local preview_window
  local curr_win = vim.api.nvim_get_current_win()
  local success, result = pcall(vim.api.nvim_win_get_var, curr_win, "is-goto-preview-window")

  if is_curr_buf(buffer) and not same_file_float_preview() then
    return curr_win
  end

  if not stack_floating_preview_windows() and is_floating(curr_win) and success and result == 1 then
    preview_window = curr_win
    vim.api.nvim_win_set_config(preview_window, {
      width = opts.width or M.conf.width,
      height = opts.height or M.conf.height,
      border = M.conf.border,
    })
    vim.api.nvim_win_set_buf(preview_window, buffer)
  else
    preview_window = vim.api.nvim_open_win(buffer, enter(), {
      relative = "win",
      width = opts.width or M.conf.width,
      height = opts.height or M.conf.height,
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
  local zindex = M.conf.zindex + (vim.tbl_isempty(M.windows) and 0 or #M.windows)

  opts = opts or {}

  local preview_window = create_preview_win(buffer, bufpos, zindex, opts)

  if M.conf.opacity then
    vim.api.nvim_set_option_value("winblend", M.conf.opacity, { win = preview_window })
  end
  if not is_curr_buf(buffer) then
    vim.api.nvim_set_option_value("bufhidden", M.conf.bufhidden, { buf = buffer })
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

  return preview_window
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

local function _open_references_window(filename, pos)
  M.open_floating_win(vim.uri_from_fname(filename), pos)
end

local function _format_item_entry(item)
  -- Format text to the following standard
  -- some/path/to/file:20:1  | text in the file
  -- some/longer/path/to/f...| text in the file
  local filename_width = 30

  -- This sets up the correct field for mini.pick
  item.path = item.filename
  local rel_path = vim.fn.fnamemodify(item.filename, ":.")
  local display_path = string.format("%s:%d:%d", rel_path, item.lnum or 1, item.col or 1)

  if #display_path > filename_width then
    display_path = display_path:sub(1, filename_width - 3) .. "..."
  else
    display_path = display_path .. string.rep(" ", filename_width - #display_path)
  end

  -- Remove leading and trailing spaces
  local trimmed = string.gsub(item.text, "^%s*(.-)%s*$", "%1")

  item.text = display_path .. "| " .. trimmed
  return item.text
end

local providers = {
  snacks = function(_, _)
    local ok, snacks = pcall(require, "snacks")
    if not ok then
      error "Snacks not installed"
    end

    snacks.picker.pick {
      source = "lsp_references",
      confirm = function(picker)
        local selection = picker:current()
        picker:close()

        if selection ~= nil then
          _open_references_window(selection.file, selection.pos)
        end
      end,
    }
  end,

  fzf_lua = function(_, _)
    local ok, fzf = pcall(require, "fzf-lua")
    if not ok then
      error "fzf-lua not installed"
    end

    fzf.lsp_references {
      actions = {
        ["default"] = function(selected, opts)
          local selection = fzf.path.entry_to_file(selected[1], opts)

          _open_references_window(
            selection.path,
            { selection.line, selection.col }
          )
        end,
      },
    }
  end,

  telescope = function(prompt_title, items)
    local ok, _ = pcall(require, "telescope")
    if not ok then
      error "Telescope not installed"
    end

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

          _open_references_window(selection.value.filename, {
            selection.value.lnum,
            selection.value.col,
          })
        end)

        return true
      end,
    }):find()
  end,

  mini_pick = function(prompt_title, items)
    local ok, mini_pick = pcall(require, "mini.pick")
    if not ok then
      error "MiniPick not installed"
    end

    for _, item in ipairs(items) do
      _format_item_entry(item)
    end

    mini_pick.start {
      source = {
        name = prompt_title,
        items = items,
        show = function(buf_id, items_to_show, query)
          mini_pick.default_show(buf_id, items_to_show, query, {
            show_icons = true,
          })
        end,
        choose = function(item)
          _open_references_window(item.filename, {
            item.lnum,
            item.col,
          })
        end,
      },
      preview = function(buf_id, item)
        mini_pick.default_preview(buf_id, item, nil)
      end,
    }
  end,

  default = function(prompt_title, items)
    vim.ui.select(items, {
      prompt = prompt_title,
      format_item = function(item)
        if item ~= nil then
          return _format_item_entry(item)
        end
      end
    }, function(choice)
      if choice ~= nil then
        _open_references_window(choice.filename, {
          choice.lnum,
          choice.col,
        })
      end
    end)
  end,
}

local function open_references_previewer(prompt_title, items)
  if #items == 1 then
    local item = items[1]
    _open_references_window(item.filename, { item.lnum, item.col })
    return true
  end

  local provider = M.conf.references.provider
  local provider_fn = providers[provider]

  -- Try selected provider first
  if provider_fn then
    local ok, err = pcall(provider_fn, prompt_title, items)
    if ok then
      return
    end
    -- Log the error and fall through to default
    logger.debug("Provider", provider, "failed:", err)
  end

  -- Fall back to default provider
  providers.default(prompt_title, items)
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
  for k, v in pairs(vim.lsp.handlers) do
    if string.find(k, "textDocument")
        and type(v) == "function"
        and debug.getinfo(v).isvararg == false
    then
      if debug.getinfo(v).nparams == 4 then
        logger.debug "calling new handler"
        return handler(lsp_call, opts)
      else
        logger.debug "calling legacy handler"
        return legacy_handler(lsp_call, opts)
      end
    end
  end
end

return M
