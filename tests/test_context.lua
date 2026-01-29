--- Tests for blink-cmp-skkeleton.context module
--- Run with: just test

local new_set = MiniTest.new_set
local expect = MiniTest.expect

local context_module = require("blink-cmp-skkeleton.context")

local T = new_set()

-- extract_pre_edit_from_line tests
T["extract_pre_edit_from_line"] = new_set()

T["extract_pre_edit_from_line"]["extracts text after henkan marker"] = function()
  local old_get_current_line = vim.api.nvim_get_current_line
  local old_get_cursor = vim.api.nvim_win_get_cursor

  vim.api.nvim_get_current_line = function()
    return "hello▽あいう world"
  end
  vim.api.nvim_win_get_cursor = function()
    -- Position after "あいう" (hello=5 + ▽=3 + あいう=9 = 17)
    return { 1, 17 }
  end

  local result = context_module.extract_pre_edit_from_line()
  expect.equality(result, "あいう")

  vim.api.nvim_get_current_line = old_get_current_line
  vim.api.nvim_win_get_cursor = old_get_cursor
end

T["extract_pre_edit_from_line"]["returns nil when no marker"] = function()
  local old_get_current_line = vim.api.nvim_get_current_line
  local old_get_cursor = vim.api.nvim_win_get_cursor

  vim.api.nvim_get_current_line = function()
    return "hello world"
  end
  vim.api.nvim_win_get_cursor = function()
    return { 1, 5 }
  end

  local result = context_module.extract_pre_edit_from_line()
  expect.equality(result, nil)

  vim.api.nvim_get_current_line = old_get_current_line
  vim.api.nvim_win_get_cursor = old_get_cursor
end

T["extract_pre_edit_from_line"]["handles empty text after marker"] = function()
  local old_get_current_line = vim.api.nvim_get_current_line
  local old_get_cursor = vim.api.nvim_win_get_cursor

  vim.api.nvim_get_current_line = function()
    return "hello▽"
  end
  vim.api.nvim_win_get_cursor = function()
    -- Position right after ▽ (hello=5 + ▽=3 = 8)
    return { 1, 8 }
  end

  local result = context_module.extract_pre_edit_from_line()
  expect.equality(result, "")

  vim.api.nvim_get_current_line = old_get_current_line
  vim.api.nvim_win_get_cursor = old_get_cursor
end

-- build_text_edit_range tests
T["build_text_edit_range"] = new_set()

T["build_text_edit_range"]["calculates correct range for ASCII"] = function()
  local context = {
    cursor = { 1, 5 }, -- line 1, column 5
  }
  local pre_edit = "test"
  local result = context_module.build_text_edit_range(context, pre_edit)

  expect.equality(result.start.line, 0) -- LSP 0-indexed
  expect.equality(result.start.character, 1) -- 5 - 4 bytes
  expect.equality(result["end"].line, 0)
  expect.equality(result["end"].character, 5)
end

T["build_text_edit_range"]["calculates correct range for multibyte"] = function()
  local context = {
    cursor = { 1, 9 }, -- line 1, column 9
  }
  local pre_edit = "▽あい" -- 3 + 3 + 3 = 9 bytes
  local result = context_module.build_text_edit_range(context, pre_edit)

  expect.equality(result.start.line, 0)
  expect.equality(result.start.character, 0) -- 9 - 9 bytes
  expect.equality(result["end"].line, 0)
  expect.equality(result["end"].character, 9)
end

T["build_text_edit_range"]["handles empty pre_edit"] = function()
  local context = {
    cursor = { 1, 5 }, -- line 1, column 5
  }
  local pre_edit = ""
  local result = context_module.build_text_edit_range(context, pre_edit)

  -- Empty pre_edit means range starts and ends at cursor
  expect.equality(result.start.line, 0)
  expect.equality(result.start.character, 5) -- 5 - 0 bytes
  expect.equality(result["end"].line, 0)
  expect.equality(result["end"].character, 5)
end

T["build_text_edit_range"]["handles cursor at column 0"] = function()
  local context = {
    cursor = { 1, 0 }, -- line 1, column 0 (line start)
  }
  local pre_edit = ""
  local result = context_module.build_text_edit_range(context, pre_edit)

  -- At line start with empty pre_edit
  expect.equality(result.start.line, 0)
  expect.equality(result.start.character, 0)
  expect.equality(result["end"].line, 0)
  expect.equality(result["end"].character, 0)
end

T["build_text_edit_range"]["handles mixed ASCII and Japanese"] = function()
  local context = {
    cursor = { 1, 15 }, -- line 1, column 15
  }
  -- "abc" (3 bytes) + "▽あい" (9 bytes) + "de" (2 bytes) = 14 bytes before cursor
  -- but pre_edit is only "▽あい" (9 bytes)
  local pre_edit = "▽あい"
  local result = context_module.build_text_edit_range(context, pre_edit)

  expect.equality(result.start.line, 0)
  expect.equality(result.start.character, 6) -- 15 - 9 bytes
  expect.equality(result["end"].line, 0)
  expect.equality(result["end"].character, 15)
end

-- extract_filter_text tests
T["extract_filter_text"] = new_set()

T["extract_filter_text"]["returns pre_edit when no bounds"] = function()
  local context = {
    cursor = { 1, 5 },
    bounds = nil,
  }
  local result = context_module.extract_filter_text(context, "test")
  expect.equality(result, "test")
end

T["extract_filter_text"]["returns pre_edit when bounds length is 0"] = function()
  local context = {
    cursor = { 1, 5 },
    bounds = { start_col = 1, length = 0 },
  }
  local result = context_module.extract_filter_text(context, "test")
  expect.equality(result, "test")
end

T["extract_filter_text"]["extracts from line using bounds"] = function()
  local old_get_current_line = vim.api.nvim_get_current_line
  vim.api.nvim_get_current_line = function()
    return "hello▽あいう world"
  end

  local context = {
    cursor = { 1, 17 },
    bounds = { start_col = 6, length = 12 }, -- "▽あいう" (3 + 9 = 12 bytes)
  }
  local result = context_module.extract_filter_text(context, "あいう")
  expect.equality(result, "▽あいう")

  vim.api.nvim_get_current_line = old_get_current_line
end

-- compute_text_edit_range tests
T["compute_text_edit_range"] = new_set()

T["compute_text_edit_range"]["uses bounds when available"] = function()
  local context = {
    cursor = { 1, 15 },
    bounds = { start_col = 6, length = 9 },
  }
  local result = context_module.compute_text_edit_range(context, "▽あい")

  expect.equality(result.start.line, 0)
  expect.equality(result.start.character, 6) -- 15 - 9 bytes
  expect.equality(result["end"].line, 0)
  expect.equality(result["end"].character, 15)
end

T["compute_text_edit_range"]["falls back to build_text_edit_range when no bounds"] = function()
  local context = {
    cursor = { 1, 5 },
    bounds = nil,
  }
  local result = context_module.compute_text_edit_range(context, "test")

  expect.equality(result.start.line, 0)
  expect.equality(result.start.character, 1) -- 5 - 4 bytes
  expect.equality(result["end"].line, 0)
  expect.equality(result["end"].character, 5)
end

T["compute_text_edit_range"]["falls back when pre_edit is empty"] = function()
  local context = {
    cursor = { 1, 5 },
    bounds = { start_col = 1, length = 5 },
  }
  local result = context_module.compute_text_edit_range(context, "")

  expect.equality(result.start.line, 0)
  expect.equality(result.start.character, 5)
  expect.equality(result["end"].line, 0)
  expect.equality(result["end"].character, 5)
end

return T
