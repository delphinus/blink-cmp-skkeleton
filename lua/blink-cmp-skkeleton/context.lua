--- Context processing module for blink.cmp integration
--- @module blink-cmp-skkeleton.context

local M = {}

--- Extract pre_edit text from current line when getPreEdit returns empty
--- Looks for the henkan marker (▽) and extracts text after it
--- @return string|nil
function M.extract_pre_edit_from_line()
  local line = vim.api.nvim_get_current_line()
  local col = vim.api.nvim_win_get_cursor(0)[2]

  -- Get the text up to cursor position
  local text_before_cursor = line:sub(1, col)

  -- Look for the henkan marker (▽) before cursor
  local marker_pos = text_before_cursor:find("▽")
  if marker_pos then
    -- Extract text after ▽ up to cursor (▽ is 3 bytes in UTF-8)
    local text_after_marker = text_before_cursor:sub(marker_pos + 3)
    return text_after_marker
  end

  return nil
end

--- Build text edit range for pre-edit replacement
--- @param context blink.cmp.Context
--- @param pre_edit string
--- @return table LSP TextEdit range
function M.build_text_edit_range(context, pre_edit)
  local cursor_line = context.cursor[1]
  local cursor_col = context.cursor[2]

  -- IMPORTANT: pre_edit_len is CHARACTER count, but cursor_col is BYTE position
  -- We need to use the actual byte length of pre_edit string
  local pre_edit_byte_len = #pre_edit
  local start_col = cursor_col - pre_edit_byte_len

  local range = {
    start = {
      line = cursor_line - 1, -- LSP uses 0-indexed lines
      character = start_col,
    },
    ["end"] = {
      line = cursor_line - 1,
      character = cursor_col,
    },
  }

  return range
end

--- Extract filter text from blink.cmp context
--- Uses context.bounds if available, otherwise returns pre_edit
--- @param context blink.cmp.Context
--- @param pre_edit string
--- @return string
function M.extract_filter_text(context, pre_edit)
  if context.bounds and context.bounds.length > 0 then
    local current_line = vim.api.nvim_get_current_line()
    local start_byte = context.bounds.start_col - 1
    local length_bytes = context.bounds.length
    return current_line:sub(start_byte + 1, start_byte + length_bytes)
  end
  return pre_edit
end

--- Compute text edit range based on context and pre_edit
--- Uses context.bounds if available for better alignment with blink.cmp
--- @param context blink.cmp.Context
--- @param pre_edit string
--- @return table LSP TextEdit range
function M.compute_text_edit_range(context, pre_edit)
  if context.bounds and pre_edit ~= "" then
    -- Use bounds to determine the range, but only replace the pre_edit portion
    local cursor_col = context.cursor[2]
    local pre_edit_byte_len = #pre_edit
    return {
      start = {
        line = context.cursor[1] - 1,
        character = cursor_col - pre_edit_byte_len,
      },
      ["end"] = {
        line = context.cursor[1] - 1,
        character = cursor_col,
      },
    }
  else
    return M.build_text_edit_range(context, pre_edit)
  end
end

return M
