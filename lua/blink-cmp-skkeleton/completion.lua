--- Completion item builder for blink-cmp-skkeleton
--- @module blink-cmp-skkeleton.completion

local M = {}

--- Build a single completion item
--- @param item blink-cmp-skkeleton.CompleteItem
--- @param index integer position of the item in skkeleton's ordering (1-based)
--- @param text_edit_range table
--- @param filter_text string|nil Filter text for blink.cmp matching
--- @return blink.cmp.CompletionItem
function M.build_completion_item(item, index, text_edit_range, filter_text)
  local completion_item = {
    label = item.word,
    kind = vim.lsp.protocol.CompletionItemKind.Text,
    -- filterText: use provided filter_text or fall back to the midashi
    filterText = filter_text or item.midasi,
    -- Use textEdit to replace the entire pre-edit text (including ▽)
    textEdit = {
      newText = item.word,
      range = text_edit_range,
    },
    -- skkeleton hands the items over already ordered (completion ranks first,
    -- then the dictionary order, then the okuriari candidates), so the position
    -- in that list is the sort key.
    sortText = string.format("%010d", index),
    data = {
      skkeleton = true,
      kana = item.midasi,
      word = item.candidate,
      henkan_type = item.henkan_type,
    },
  }

  if item.info ~= "" then
    completion_item.documentation = {
      kind = "plaintext",
      value = item.info,
    }
  end

  return completion_item
end

--- Build completion items from skkeleton's complete items
--- @param items blink-cmp-skkeleton.CompleteItem[]
--- @param text_edit_range table
--- @param filter_text string|nil Filter text for blink.cmp matching
--- @return blink.cmp.CompletionItem[]
function M.build_completion_items(items, text_edit_range, filter_text)
  local completion_items = {}

  for index, item in ipairs(items) do
    table.insert(completion_items, M.build_completion_item(item, index, text_edit_range, filter_text))
  end

  return completion_items
end

return M
