## Goto Preview
A small Neovim plugin for previewing the result of a native lsp goto-definition or goto-implementation call in a floating window.

### Showcase
<img src="https://github.com/rmagatti/readme-assets/blob/main/goto-preview-zoomed.gif" />

### IMPORTANT NOTE
There is currently an open [Neovim TUI](https://github.com/neovim/neovim/issues/14735) bug that prevents the correct positioning of more than one preview window.
One singular preview window should work fine but jumping to a subsequent preview will position it in an undesired spot.

GUIs like [Goneovim](https://github.com/akiyosi/goneovim) and [Uivonim](https://github.com/smolck/uivonim) implement the correct positioning behaviour and will behave as intended.


### Installation
Packer.nvim
```lua
use {
  'rmagatti/goto-preview',
  config = function()
    require('goto-preview').setup {}
  end
}
```

### Configuration
**Default**
```lua
require('goto-preview').setup {
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
```

### Mappings
There are no mappings by default, you can set `default_mappings = true` in the config to make use of the mappings I use or define your own.
**Default**
```viml
nnoremap gpd <cmd>lua require('goto-preview').goto_preview_definition()<CR>
nnoremap gpi <cmd>lua require('goto-preview').goto_preview_implementation()<CR>
nnoremap gP <cmd>lua require('goto-preview').close_all_win()<CR>
```

**Custom example**
```lua
vim.api.nvim_set_keymap("n", "gp", "<cmd>lua require('goto-preview').goto_preview_definition()<CR>", {noremap=true})
```

If you have [Vimpeccable](https://github.com/svermeulen/vimpeccable) installed it'll use it to create the mappings, if not, builtin `nvim_set_keymap` will be used.

### Supported languages
Goto Preview comes with Lua and Typescript pre-configured since those are the ones I needed at the time. Please do submit a PR to add more pre-configured LSP responses!

**Note:** different language servers have potentially different shapes for the result of the `textDocument/definition` and `textDocument/implementation` calls.
Until more are added one can pass in custom responses through the `lsp_configs` config value. Just follow the same pattern returning two values, a `target (string)` and a `cursor_position ({line_num, col_num})`. The `data` parameter is the `[1]` of the LSP's `result` of the definition/implementation calls and is what gets passed into the custom `get_config` function.


### Tested with
NVIM v0.5.0-dev+7d4f890aa  
Build type: Release  
LuaJIT 2.1.0-beta3  
