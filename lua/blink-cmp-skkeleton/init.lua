--- blink.cmp source for skkeleton
--- Based on skkeleton's ddc.vim source implementation
--- Adapted for blink.cmp native API
--- @module blink-cmp-skkeleton

local utils = require("blink-cmp-skkeleton.utils")
local skkeleton = require("blink-cmp-skkeleton.skkeleton")
local completion = require("blink-cmp-skkeleton.completion")
local context_module = require("blink-cmp-skkeleton.context")
local triggers = require("blink-cmp-skkeleton.triggers")

-- Module-level cache for trigger characters
local trigger_characters_cache = nil

--- @class blink.cmp.Source
local source = {}

--- Check if skkeleton is currently enabled
--- This is a public helper function for use in sources.default configuration
--- @return boolean
function source.is_enabled()
  return skkeleton.is_enabled()
end

--- Create a new source instance
--- @param opts? table Options
--- @return blink.cmp.Source
function source.new(opts)
  local self = setmetatable({}, { __index = source })
  self.opts = opts or {}
  return self
end

--- Check if skkeleton is available
--- @return boolean
function source:enabled()
  return vim.fn.exists("*skkeleton#is_enabled") == 1
end

--- Get trigger characters for completion
--- @return string[]
function source:get_trigger_characters()
  -- Return hiragana and katakana characters as triggers
  -- This ensures that completion is triggered after accepting a completion
  -- and continuing to type Japanese characters
  if not trigger_characters_cache then
    trigger_characters_cache = triggers.generate_japanese()
    utils.debug_log(string.format("Generated %d trigger characters", #trigger_characters_cache))
  end
  return trigger_characters_cache
end

--- Get completions from skkeleton
--- @param context blink.cmp.Context
--- @param callback fun(response: { is_incomplete_forward: boolean, is_incomplete_backward: boolean, items: blink.cmp.CompletionItem[] })
--- @return function cancel function
function source:get_completions(context, callback)
  -- Cancel function (no-op for now since we don't have async operations)
  local cancel_fun = function() end

  -- Debug: Log basic information
  utils.debug_log(
    string.format(
      "get_completions: line=%d, col=%d, trigger=%s",
      context.cursor[1],
      context.cursor[2],
      context.trigger and context.trigger.kind or "nil"
    )
  )

  -- Check if skkeleton is enabled
  if not skkeleton.is_enabled() then
    utils.debug_log("skkeleton not enabled, returning empty")
    callback({
      is_incomplete_forward = false,
      is_incomplete_backward = false,
      items = {},
    })
    return cancel_fun
  end

  -- Get completion data from skkeleton via denops
  local candidates, ranks_array, pre_edit = skkeleton.get_completion_data()

  -- Convert ranks and build items
  local ranks = completion.convert_ranks_to_map(ranks_array)

  -- Compute text_edit_range using context module
  local text_edit_range = context_module.compute_text_edit_range(context, pre_edit)

  -- Extract filterText using context module
  local filter_text = context_module.extract_filter_text(context, pre_edit)

  local items = completion.build_completion_items(candidates, ranks, text_edit_range, filter_text)

  utils.debug_log(string.format("Returning %d items for pre_edit='%s'", #items, pre_edit))

  -- Wrap callback in vim.schedule_wrap
  local wrapped_callback = vim.schedule_wrap(function()
    callback({
      is_incomplete_forward = true, -- Tell blink.cmp not to filter
      is_incomplete_backward = true,
      items = items,
    })
  end)

  wrapped_callback()
  return cancel_fun
end

--- Resolve additional information for a completion item
--- @param item blink.cmp.CompletionItem
--- @param callback fun(resolved_item: blink.cmp.CompletionItem|nil)
function source:resolve(item, callback)
  callback(item)
end

--- Execute completion (called when item is confirmed)
--- @param context blink.cmp.Context
--- @param item blink.cmp.CompletionItem
--- @param callback fun()
--- @param default_implementation fun()
function source:execute(context, item, callback, default_implementation)
  if not item.data or not item.data.skkeleton then
    default_implementation()
    return callback()
  end

  utils.debug_log(string.format("execute: kana=%s, word=%s", item.data.kana, item.data.word))

  -- First, let blink.cmp insert the text
  default_implementation()

  -- Then, register the result with skkeleton for dictionary learning
  local henkan_type = utils.determine_henkan_type(item.data.kana)
  skkeleton.register_completion(item.data.kana, item.data.word, henkan_type)

  callback()
end

return source
