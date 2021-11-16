local has_telescope, telescope = pcall(require, "telescope")
local GotoPreview = require("goto-preview")
local lib = require("goto-preview.lib")

if not has_telescope then
  lib.logger.debug("Telescope.nvim not found. (https://github.com/nvim-telescope/telescope.nvim)")
end

return telescope.register_extension({
  setup = GotoPreview.setup,
  exports = {
    references = GotoPreview.goto_preview_references,
  },
})
