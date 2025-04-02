local M = {}

function M.check()
  -- Use vim.health in Neovim 0.8+ or health in older versions if available
  local health
  if vim.fn.has('nvim-0.8') == 1 then
    health = vim.health
  else
    health = require('health')
  end

  -- Start the health check report
  health.start("goto-preview")

  -- Check if logger.nvim is installed
  local has_logger, _ = pcall(require, "logger")
  if has_logger then
    health.ok("logger.nvim is installed")
  else
    health.warn("logger.nvim is not installed", {
      "Some advanced logging features will be limited",
      "Consider installing 'logger.nvim' for enhanced logging capabilities",
      "To do so, add `dependencies = 'rmagatti/logger.nvim'` to the plugin install object"
    })
  end

  -- Check if the plugin is properly loaded
  local has_goto_preview = pcall(require, "goto-preview")
  if has_goto_preview then
    health.ok("goto-preview is properly loaded")
  else
    health.error("goto-preview is not properly loaded")
  end

  -- Check for other providers
  health.info("Checking available reference providers")

  -- Telescope
  local has_telescope = pcall(require, "telescope")
  if has_telescope then
    health.ok("Telescope is available for references provider")
  else
    health.info("Telescope is not installed (optional for 'telescope' references provider)")
  end

  -- fzf-lua
  local has_fzf = pcall(require, "fzf-lua")
  if has_fzf then
    health.ok("fzf-lua is available for references provider")
  else
    health.info("fzf-lua is not installed (optional for 'fzf_lua' references provider)")
  end

  -- mini.pick
  local has_mini_pick = pcall(require, "mini.pick")
  if has_mini_pick then
    health.ok("mini.pick is available for references provider")
  else
    health.info("mini.pick is not installed (optional for 'mini_pick' references provider)")
  end

  -- snacks
  local has_snacks = pcall(require, "snacks")
  if has_snacks then
    health.ok("snacks is available for references provider")
  else
    health.info("snacks is not installed (optional for 'snacks' references provider)")
  end
end

return M


