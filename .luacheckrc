-- Luacheck configuration for Neovim plugins
max_line_length = 120

-- Define globals that are available in Neovim
globals = {
  "vim",
}

-- Read-only globals
read_globals = {
  "vim",
}

-- Ignore certain warnings
ignore = {
  "631", -- Line is too long (handled by max_line_length)
  "212", -- Unused argument (common in callbacks)
  "213", -- Unused loop variable (common with ipairs)
}

-- Allow unused arguments (common in callback functions)
unused_args = false

-- File-specific configurations
files = {
  ["tests/*"] = {
    globals = {
      "describe",
      "it",
      "before_each", 
      "after_each",
      "assert",
      "_G",
      "package",
    }
  }
}
