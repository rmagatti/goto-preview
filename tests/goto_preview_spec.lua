-- goto-preview test specifications
-- Tests the get_config function and handler detection for LSP responses

-- Mock vim global to prevent errors during testing
if not vim then
  _G.vim = {
    notify = function(msg, level) print("[NOTIFY]:", msg) end,
    log = { levels = { WARN = 2 } },
    inspect = function(obj) return tostring(obj) end,
    tbl_deep_extend = function(behavior, ...)
      local result = {}
      local function merge(t)
        for k, v in pairs(t) do
          if type(v) == "table" and type(result[k]) == "table" then
            result[k] = vim.tbl_deep_extend(behavior, result[k], v)
          else
            result[k] = v
          end
        end
      end
      for _, t in ipairs({...}) do
        merge(t)
      end
      return result
    end,
    tbl_isempty = function(t)
      return next(t) == nil
    end,
    api = {
      nvim_get_current_buf = function() return 1 end,
      nvim_get_current_win = function() return 1 end,
      nvim_win_get_config = function() return { relative = "" } end,
      nvim_win_get_var = function() return nil end,
    },
    lsp = {
      handlers = {
        ["textDocument/definition"] = function(err, result, ctx, config) end,
        ["textDocument/typeDefinition"] = function(err, result, ctx, config) end,
      },
      get_clients = function() return {} end,
    },
    fn = {
      has = function() return 1 end,
    },
  }
end

-- Test helper functions
local function create_lsp_location_response(uri, line, character)
  return {
    uri = uri,
    range = {
      start = {
        line = line or 0,
        character = character or 0,
      },
      ["end"] = {
        line = (line or 0) + 1,
        character = (character or 0) + 10,
      },
    },
  }
end

local function create_lsp_definition_response(targetUri, line, character)
  return {
    targetUri = targetUri,
    targetRange = line and {
      start = {
        line = line,
        character = character or 0,
      },
      ["end"] = {
        line = line + 1,
        character = (character or 0) + 10,
      },
    } or nil,
  }
end

describe("goto-preview", function()
  local goto_preview
  local lib

  before_each(function()
    -- Clear package cache to get fresh modules
    package.loaded["goto-preview"] = nil
    package.loaded["goto-preview.lib"] = nil
    
    -- Setup goto-preview with minimal config
    goto_preview = require("goto-preview")
    lib = require("goto-preview.lib")
    
    goto_preview.setup({
      debug = true,
      lsp_configs = {
        get_config = function(data)
          local uri = data.targetUri or data.uri
          local range = data.targetRange or data.range

          if range == nil then
            vim.notify("Range is nil, returning default configuration.", vim.log.levels.WARN)
            return uri, { 1, 0 }
          end

          return uri, { range.start.line + 1, range.start.character }
        end,
      },
    })
  end)

  describe("get_config function", function()
    it("should handle nil range without panicking", function()
      local get_config = goto_preview.conf.lsp_configs.get_config
      local test_data = create_lsp_definition_response("file:///test.lua", nil)
      
      -- This should not panic and should return safe defaults
      local uri, pos = get_config(test_data)
      
      assert.equals("file:///test.lua", uri)
      assert.same({ 1, 0 }, pos)
    end)

    it("should handle valid range correctly", function()
      local get_config = goto_preview.conf.lsp_configs.get_config
      local test_data = create_lsp_definition_response("file:///test.lua", 5, 10)
      
      local uri, pos = get_config(test_data)
      
      assert.equals("file:///test.lua", uri)
      assert.same({ 6, 10 }, pos) -- line is 0-indexed in LSP, so 5 becomes 6
    end)

    it("should handle LSP location format (uri/range)", function()
      local get_config = goto_preview.conf.lsp_configs.get_config
      local test_data = create_lsp_location_response("file:///location.lua", 3, 7)
      
      local uri, pos = get_config(test_data)
      
      assert.equals("file:///location.lua", uri)
      assert.same({ 4, 7 }, pos) -- line is 0-indexed in LSP, so 3 becomes 4
    end)

    it("should handle definition format (targetUri/targetRange)", function()
      local get_config = goto_preview.conf.lsp_configs.get_config
      local test_data = {
        targetUri = "file:///definition.lua",
        targetRange = {
          start = { line = 10, character = 5 },
        },
      }
      
      local uri, pos = get_config(test_data)
      
      assert.equals("file:///definition.lua", uri)
      assert.same({ 11, 5 }, pos)
    end)
  end)

  describe("handler detection", function()
    it("should detect modern handler path (4 params)", function()
      -- Mock handlers that use modern signature (err, result, ctx, config)
      vim.lsp.handlers = {
        ["textDocument/definition"] = function(err, result, ctx, config)
          return result
        end,
      }
      
      local handler = lib.get_handler("textDocument/definition", {})
      assert.is_not_nil(handler)
      
      -- Test that the handler works and doesn't panic
      local success, result = pcall(handler, nil, { uri = "file:///test.lua", range = { start = { line = 0, character = 0 } } }, nil, nil)
      assert.is_true(success)
    end)

    it("should detect legacy handler path (3 params)", function()
      -- Mock handlers that use legacy signature (client_id, method, result)
      vim.lsp.handlers = {
        ["textDocument/definition"] = function(client_id, method, result)
          return result
        end,
      }
      
      local handler = lib.get_handler("textDocument/definition", {})
      assert.is_not_nil(handler)
      
      -- Test that the handler works and doesn't panic
      local success, result = pcall(handler, nil, nil, { uri = "file:///test.lua", range = { start = { line = 0, character = 0 } } })
      assert.is_true(success)
    end)
  end)

  describe("LSP response handling", function()
    it("should handle empty results gracefully", function()
      local get_config = goto_preview.conf.lsp_configs.get_config
      
      -- Test with empty table
      local uri, pos = get_config({})
      assert.same({ 1, 0 }, pos)
      
      -- Test with nil uri but valid range
      local test_data = {
        range = { start = { line = 5, character = 2 } },
      }
      uri, pos = get_config(test_data)
      assert.same({ 6, 2 }, pos)
    end)

    it("should handle malformed range data", function()
      local get_config = goto_preview.conf.lsp_configs.get_config
      
      -- Test with range but no start
      local test_data = {
        uri = "file:///test.lua",
        range = {},
      }
      
      -- This should use the nil range path and return defaults
      local uri, pos = get_config(test_data)
      assert.equals("file:///test.lua", uri)
      assert.same({ 1, 0 }, pos)
    end)
  end)
end)

