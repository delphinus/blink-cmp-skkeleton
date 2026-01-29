--- Skkeleton and denops integration layer
--- @module blink-cmp-skkeleton.skkeleton

local utils = require("blink-cmp-skkeleton.utils")
local cache_module = require("blink-cmp-skkeleton.cache")
local context_module = require("blink-cmp-skkeleton.context")

local M = {}

-- Cache instance
local cache = cache_module.new()

--- Request data from skkeleton via denops
--- @param key string
--- @param args? any[]
--- @return unknown
local function request(key, args)
  args = args or {}
  local ok, result = pcall(vim.fn["denops#request"], "skkeleton", key, args)
  return ok and result or nil
end

--- Clear cache and reset statistics (public for testing)
function M.clear_cache()
  cache.clear()
end

--- Get cache statistics
--- @return table stats { hits: number, misses: number, hit_rate: number }
function M.get_cache_stats()
  return cache.get_stats()
end

--- Check if skkeleton is available and enabled
--- @return boolean
function M.is_enabled()
  local result = utils.safe_call(vim.fn["skkeleton#is_enabled"])
  return result == true or result == 1
end

--- Get completion data from skkeleton (with caching)
--- @return table candidates, table ranks_array, string pre_edit
function M.get_completion_data()
  -- Step 1: Get current cursor position
  local cursor_pos = vim.api.nvim_win_get_cursor(0)
  local cursor_line = cursor_pos[1]
  local cursor_col = cursor_pos[2]

  -- Step 2: Get pre_edit (lightweight RPC)
  local pre_edit = request("getPreEdit") or ""

  -- Step 2.5: If pre_edit is empty, try to extract from current line
  if pre_edit == "" then
    local extracted = context_module.extract_pre_edit_from_line()
    if extracted then
      pre_edit = extracted
      utils.debug_log(string.format("Extracted pre_edit: '%s'", pre_edit))
    end
  end

  -- Step 3: Check if we can use cached data
  -- Use cache if:
  -- a) pre_edit matches the cached key, OR
  -- b) pre_edit is empty AND cursor position hasn't changed (rapid consecutive calls)
  local cached_data = cache.get(pre_edit)

  if not cached_data and pre_edit == "" then
    -- If pre_edit is empty but we're at the same cursor position, use cache
    local state = cache.get_state()
    if state.meta then
      local same_position = (state.meta[1] == cursor_line and state.meta[2] == cursor_col)
      local cache_age = vim.loop.now() - state.timestamp

      if same_position and cache_age < cache.get_ttl() then
        utils.debug_log(string.format("Using cache at same position (age=%dms)", cache_age))
        -- Re-fetch from cache using the original key
        cached_data = cache.get(state.key)
      end
    end
  end

  if cached_data then
    local stats = cache.get_stats()
    local hit_rate = stats.hit_rate
    utils.debug_log(
      string.format(
        "Cache HIT for '%s' (total: %d/%d, %.1f%%)",
        pre_edit,
        stats.hits,
        stats.hits + stats.misses,
        hit_rate
      )
    )
    return cached_data.candidates, cached_data.ranks, cached_data.pre_edit
  end

  -- Step 4: Cache miss - fetch data
  utils.debug_log(string.format("Cache MISS for '%s', fetching...", pre_edit))

  local candidates = request("getCompletionResult") or {}
  local ranks_array = request("getRanks") or {}

  utils.debug_log(string.format("pre_edit='%s', candidates=%d", pre_edit, #candidates))

  -- Step 5: Update cache with cursor position
  cache.set(pre_edit, {
    candidates = candidates,
    ranks = ranks_array,
    pre_edit = pre_edit,
  }, { cursor_line, cursor_col })

  return candidates, ranks_array, pre_edit
end

--- Register completion result with skkeleton for dictionary learning
--- @param kana string
--- @param word string
--- @param henkan_type "okuriari"|"okurinasi"
function M.register_completion(kana, word, henkan_type)
  utils.debug_log(string.format("register: kana=%s, word=%s, type=%s", kana, word, henkan_type))
  request("completeCallback", { kana, word, henkan_type })

  -- Clear cache after dictionary learning (ranks may change)
  M.clear_cache()
end

return M
