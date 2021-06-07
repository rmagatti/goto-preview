local M = {
  conf = {
    width = 120;
    height = 15;
    default_mappings = false;
    lsp_configs = {
      lua = {
        get_config = function(data)
          return data.targetUri,{ data.targetRange.start.line + 1, data.targetRange.start.character }
        end
      };
      typescript = {
        get_config = function(data)
          return data.uri, { data.range.start.line + 1, data.range.start.character }
        end
      }
    }
  }
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
  local buffer = vim.api.nvim_create_buf(false, false)
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

  -- vim.api.nvim_win_set_option(new_window, "winblend", 15)
  vim.api.nvim_buf_set_option(buffer, 'bufhidden', 'wipe') -- necessary?

  table.insert(windows, new_window)

  -- print(vim.inspect({
  --   windows = windows,
  --   curr_window = curr_window,
  --   new_window = new_window,
  --   bufpos = bufpos,
  --   get_config = vim.api.nvim_win_get_config(new_window),
  --   get_current_line = vim.api.nvim_get_current_line()
  -- }))

  vim.cmd("e "..target)
  vim.cmd[[
    augroup close_float
      au!
      au WinClosed * lua require('goto-preview').remove_curr_win()
    augroup end
  ]]

  vim.api.nvim_win_set_cursor(new_window, position)
end

local handler = function(_, _, result)
  if not result then return end

  local data = result[1]

  local target = nil
  local cursor_position = {}

  -- The contents of `data` is different depending on the language server :(
  target, cursor_position = M.conf.lsp_configs[vim.bo.filetype].get_config(data)

  open_floating_win(target, cursor_position)
end

M.lsp_request = function(definition)
  return function()
    local params = vim.lsp.util.make_position_params()
    if definition then
      local success, _ = pcall(vim.lsp.buf_request, 0, "textDocument/definition", params, handler)
      if not success then
        print('goto-preview: Error calling LSP "textDocument/definition". The current language lsp might not support it.')
      end
    else
      local success, _ = pcall(vim.lsp.buf_request, 0, "textDocument/implementation", params, handler)
      if not success then
        print('goto-preview: Error calling LSP "textDocument/implementation". The current language lsp might not support it.')
      end
    end
  end
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

-- Mappings
M.apply_default_mappings = function()
  local has_vimp, vimp = pcall(require, "vimp")
  if not has_vimp then
    print('{default_mappings = true} option requires vimpeccable "vimp" to exist.')
  end
  if M.conf.default_mappings and has_vimp then
    vimp.unmap_all()
    vimp.nnoremap('gpi', M.lsp_request(false))
    vimp.nnoremap('gpd', M.lsp_request(true))
    vimp.nnoremap('gP', M.close_all_win)

    -- Resize windows
    vimp.nnoremap('<left>', '<C-w><')
    vimp.nnoremap('<right>', '<C-w>>')
    vimp.nnoremap('<up>', '<C-w>-')
    vimp.nnoremap('<down>', '<C-w>+')
  end
end

return M

