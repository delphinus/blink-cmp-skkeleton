--- Skkeleton and denops integration layer
--- @module blink-cmp-skkeleton.skkeleton

local utils = require("blink-cmp-skkeleton.utils")
local cache_module = require("blink-cmp-skkeleton.cache")
local context_module = require("blink-cmp-skkeleton.context")

local M = {}

-- Cache instance
local cache = cache_module.new()

--- Request data from skkeleton via denops (synchronous, blocks the UI)
--- @param key string
--- @param args? any[]
--- @return unknown
local function request(key, args)
  args = args or {}
  local ok, result = pcall(vim.fn["denops#request"], "skkeleton", key, args)
  return ok and result or nil
end

--- Request data from skkeleton via denops (asynchronous, never blocks the UI)
--- @param key string
--- @param on_success fun(result: unknown)
--- @param on_failure? fun(err: unknown)
local function request_async(key, on_success, on_failure)
  local ok = pcall(vim.fn["denops#request_async"], "skkeleton", key, {}, function(result)
    on_success(result)
  end, function(err)
    if on_failure then
      on_failure(err)
    end
  end)
  -- denops#request_async itself can throw (e.g. server not yet running). Treat
  -- that the same as an RPC failure so the caller always gets a response.
  if not ok and on_failure then
    on_failure(nil)
  end
end

--- Resolve pre_edit, falling back to extracting it from the current line when
--- skkeleton reports an empty value. Shared by the sync and async fetchers.
--- @param raw string|nil value returned by getPreEdit
--- @return string
local function normalize_pre_edit(raw)
  local pre_edit = raw or ""
  if pre_edit == "" then
    local extracted = context_module.extract_pre_edit_from_line()
    if extracted then
      pre_edit = extracted
      utils.debug_log(string.format("Extracted pre_edit: '%s'", pre_edit))
    end
  end
  return pre_edit
end

--- Look up cached completion data for a pre_edit / cursor position.
--- Mirrors the original caching strategy: use the cache when the pre_edit
--- matches, or when pre_edit is empty but the cursor has not moved (rapid
--- consecutive calls).
--- @param pre_edit string
--- @param cursor_line integer
--- @param cursor_col integer
--- @return table|nil cached_data { candidates, ranks, pre_edit }
local function lookup_cache(pre_edit, cursor_line, cursor_col)
  local cached_data = cache.get(pre_edit)

  if not cached_data and pre_edit == "" then
    local state = cache.get_state()
    if state.meta then
      local same_position = (state.meta[1] == cursor_line and state.meta[2] == cursor_col)
      local cache_age = vim.loop.now() - state.timestamp
      if same_position and cache_age < cache.get_ttl() then
        utils.debug_log(string.format("Using cache at same position (age=%dms)", cache_age))
        cached_data = cache.get(state.key)
      end
    end
  end

  if cached_data then
    local stats = cache.get_stats()
    utils.debug_log(
      string.format(
        "Cache HIT for '%s' (total: %d/%d, %.1f%%)",
        pre_edit,
        stats.hits,
        stats.hits + stats.misses,
        stats.hit_rate
      )
    )
  end

  return cached_data
end

--- Store freshly fetched completion data in the cache.
--- @param pre_edit string
--- @param candidates any[]
--- @param ranks_array any[]
--- @param cursor_line integer
--- @param cursor_col integer
local function store_cache(pre_edit, candidates, ranks_array, cursor_line, cursor_col)
  cache.set(pre_edit, {
    candidates = candidates,
    ranks = ranks_array,
    pre_edit = pre_edit,
  }, { cursor_line, cursor_col })
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

--- Get completion data from skkeleton (synchronous, with caching).
--- Kept for callers that need a blocking result; new code should prefer
--- get_completion_data_async to avoid freezing the UI on slow dictionaries
--- (e.g. an skkserv that falls back to a network lookup).
--- @return table candidates, table ranks_array, string pre_edit
function M.get_completion_data()
  local cursor_pos = vim.api.nvim_win_get_cursor(0)
  local cursor_line = cursor_pos[1]
  local cursor_col = cursor_pos[2]

  local pre_edit = normalize_pre_edit(request("getPreEdit"))

  local cached_data = lookup_cache(pre_edit, cursor_line, cursor_col)
  if cached_data then
    return cached_data.candidates, cached_data.ranks, cached_data.pre_edit
  end

  utils.debug_log(string.format("Cache MISS for '%s', fetching...", pre_edit))
  local candidates = request("getCompletionResult") or {}
  local ranks_array = request("getRanks") or {}
  utils.debug_log(string.format("pre_edit='%s', candidates=%d", pre_edit, #candidates))

  store_cache(pre_edit, candidates, ranks_array, cursor_line, cursor_col)
  return candidates, ranks_array, pre_edit
end

--- Get completion data from skkeleton without blocking the UI.
--- Issues the getPreEdit / getCompletionResult / getRanks RPCs via
--- denops#request_async and invokes `callback` once the data is ready. The
--- same caching strategy as the synchronous variant is applied.
--- @param callback fun(candidates: table, ranks_array: table, pre_edit: string)
function M.get_completion_data_async(callback)
  local cursor_pos = vim.api.nvim_win_get_cursor(0)
  local cursor_line = cursor_pos[1]
  local cursor_col = cursor_pos[2]

  request_async("getPreEdit", function(raw_pre_edit)
    local pre_edit = normalize_pre_edit(raw_pre_edit)

    local cached_data = lookup_cache(pre_edit, cursor_line, cursor_col)
    if cached_data then
      callback(cached_data.candidates, cached_data.ranks, cached_data.pre_edit)
      return
    end

    utils.debug_log(string.format("Cache MISS for '%s', fetching (async)...", pre_edit))
    request_async("getCompletionResult", function(raw_candidates)
      local candidates = raw_candidates or {}
      request_async("getRanks", function(raw_ranks)
        local ranks_array = raw_ranks or {}
        store_cache(pre_edit, candidates, ranks_array, cursor_line, cursor_col)
        utils.debug_log(string.format("pre_edit='%s', candidates=%d", pre_edit, #candidates))
        callback(candidates, ranks_array, pre_edit)
      end, function()
        -- getRanks failed: still surface candidates with empty ranks
        store_cache(pre_edit, candidates, {}, cursor_line, cursor_col)
        callback(candidates, {}, pre_edit)
      end)
    end, function()
      callback({}, {}, pre_edit)
    end)
  end, function()
    callback({}, {}, "")
  end)
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
