set rtp+=.
set rtp+=tests/

" Add plenary.nvim to runtime path (assume it's in parent directory for CI)
if isdirectory('../plenary.nvim')
  set rtp+=../plenary.nvim/
endif

" Try to find plenary in common locations
if isdirectory(expand('~/.local/share/nvim/lazy/plenary.nvim'))
  execute 'set rtp+=' . expand('~/.local/share/nvim/lazy/plenary.nvim')
endif

if isdirectory(expand('~/.local/share/nvim/site/pack/packer/start/plenary.nvim'))
  execute 'set rtp+=' . expand('~/.local/share/nvim/site/pack/packer/start/plenary.nvim')
endif

if isdirectory(expand('~/.vim/plugged/plenary.nvim'))
  execute 'set rtp+=' . expand('~/.vim/plugged/plenary.nvim')
endif

runtime! plugin/plenary.vim

" Disable swap files and backup files for testing
set noswapfile
set nobackup
set nowritebackup

" Set up basic LSP mock
lua << EOF
-- Minimal vim API mocks for testing
vim.lsp = vim.lsp or {}
vim.lsp.handlers = vim.lsp.handlers or {}
vim.lsp.util = vim.lsp.util or {}
vim.lsp.buf = vim.lsp.buf or {}

-- Mock basic LSP functions
vim.lsp.get_clients = function() return {} end
vim.lsp.buf_request = function() return true end
vim.lsp.util.make_position_params = function() return {} end
vim.lsp.util.locations_to_items = function() return {} end

-- Mock vim.ui
vim.ui = vim.ui or {}
vim.ui.select = function(items, opts, callback) 
  if callback then callback(items[1]) end
end
vim.ui.input = function(opts, callback)
  if callback then callback("test") end
end

-- Mock vim.uri functions
vim.uri_from_fname = function(fname) return "file://" .. fname end
vim.uri_to_bufnr = function(uri) return 1 end

-- Mock vim.keymap
vim.keymap = vim.keymap or {}
vim.keymap.set = function() end

-- Mock vim.cmd
vim.cmd = function() end

-- Mock vim.schedule_wrap
vim.schedule_wrap = function(fn) return fn end

-- Mock vim.list_extend
vim.list_extend = function(dst, src) 
  for _, v in ipairs(src) do
    table.insert(dst, v)
  end
  return dst
end
EOF
