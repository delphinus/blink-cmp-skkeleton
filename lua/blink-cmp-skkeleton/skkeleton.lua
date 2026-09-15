--- Skkeleton and denops integration layer
--- @module blink-cmp-skkeleton.skkeleton

--- A candidate as skkeleton hands it over through getCompleteItems.
--- @class blink-cmp-skkeleton.CompleteItem
--- @field word string text to insert (okurigana included for okuriari)
--- @field info string annotation, empty when the candidate has none
--- @field midasi string midashi the candidate was looked up under
--- @field candidate string raw candidate, annotation included
--- @field henkan_type "okurinasi"|"okuriari"

local utils = require("blink-cmp-skkeleton.utils")
local cache_module = require("blink-cmp-skkeleton.cache")

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

--- Look up cached completion data for a pre_edit / cursor position.
--- Mirrors the original caching strategy: use the cache when the pre_edit
--- matches, or when pre_edit is empty but the cursor has not moved (rapid
--- consecutive calls).
--- @param pre_edit string
--- @param cursor_line integer
--- @param cursor_col integer
--- @return table|nil cached_data { items, pre_edit }
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

--- Decode one item of getCompleteItems into the shape the rest of the plugin
--- works with. skkeleton ships the bookkeeping it needs back at confirm time
--- (midashi, raw candidate, henkan type) as JSON in user_data.
--- @param raw table item as returned by getCompleteItems
--- @return blink-cmp-skkeleton.CompleteItem|nil
local function decode_item(raw)
  if type(raw) ~= "table" or type(raw.word) ~= "string" or type(raw.user_data) ~= "string" then
    return nil
  end
  local ok, metadata = pcall(vim.json.decode, raw.user_data)
  if not ok or type(metadata) ~= "table" or metadata.tag ~= "skkeleton" then
    return nil
  end
  return {
    -- 送りありの候補では、word は送り仮名まで含んだ挿入用の文字列になっている
    word = raw.word,
    info = raw.info or "",
    midasi = metadata.midasi,
    candidate = metadata.word,
    henkan_type = metadata.type,
  }
end

--- Decode a getCompleteItems response, dropping anything unparsable.
--- @param raw_items any[]
--- @return blink-cmp-skkeleton.CompleteItem[]
local function decode_items(raw_items)
  local items = {}
  for _, raw in ipairs(raw_items) do
    local item = decode_item(raw)
    if item then
      table.insert(items, item)
    end
  end
  return items
end

--- Drop items whose midashi does not line up with `prefix`.
--- skkserv completion ("1<prefix> ") only ever returns midashis that begin with
--- the prefix, so an okurinasi candidate that fails this check came from a stale
--- skkeleton state and must not be shown. An okuriari midashi is the reading cut
--- at the okurigana ("あたり" -> "あたr"), so the part before the trailing
--- romanized okurigana is what has to be a prefix of the reading. UTF-8
--- byte-prefix matching coincides with character-prefix matching, so a plain
--- `sub` comparison is correct.
--- @param items blink-cmp-skkeleton.CompleteItem[]
--- @param prefix string
--- @return blink-cmp-skkeleton.CompleteItem[]
local function filter_items_by_prefix(items, prefix)
  if prefix == "" then
    return items
  end
  local filtered = {}
  for _, item in ipairs(items) do
    local midasi = item.midasi
    if type(midasi) == "string" then
      local matched
      if item.henkan_type == "okuriari" then
        local stem = midasi:gsub("%a$", "")
        matched = prefix:sub(1, #stem) == stem
      else
        matched = midasi:sub(1, #prefix) == prefix
      end
      if matched then
        table.insert(filtered, item)
      end
    end
  end
  return filtered
end

--- Store freshly fetched completion data in the cache.
--- @param pre_edit string
--- @param items blink-cmp-skkeleton.CompleteItem[]
--- @param cursor_line integer
--- @param cursor_col integer
local function store_cache(pre_edit, items, cursor_line, cursor_col)
  cache.set(pre_edit, {
    items = items,
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

--- Get completion items from skkeleton without blocking the UI.
---
--- getCompleteItems returns the okurinasi candidates (completion ranks already
--- applied) followed by the okuriari ones, which skkeleton finds by splitting
--- the reading at every position and looking each piece up ("あたり" ->
--- "あた*り" => 辺り, "あ*たり" => 当たり). It is the same set of candidates
--- skkeleton's two ddc sources produce together.
---
--- Because the RPCs are no longer atomic (the user can keep typing between each
--- async round-trip), the reading and the candidates could otherwise be read
--- from different skkeleton states and end up mismatched. Three guards keep them
--- consistent:
---  1. getPrefix (= state.henkanFeed, the exact key candidates are generated
---     from) is read first, and items whose midashi does not line up with that
---     prefix are dropped, so candidates from an unrelated reading never
---     surface.
---  2. getPrefix is read AGAIN after the items have been fetched. If
---     state.henkanFeed changed at any point during the fetch, the reading
---     (getPreEdit) and the items may have been read from different states --
---     the whole result is discarded. This is what stops the candidate/reading
---     mismatch the per-item filter cannot: the filter only ties candidates to
---     the prefix, not the prefix to the displayed pre_edit, so without this
---     bracket a keystroke landing between getPrefix and getPreEdit would
---     surface (filter-passing) candidates under an unrelated reading.
---  3. An empty prefix means skkeleton is not in input state, so we return empty
---     instead of falling back to the buffer.
--- A `should_cancel` predicate lets a superseded request bail out without
--- polluting the (single-slot) cache.
--- @param callback fun(items: blink-cmp-skkeleton.CompleteItem[], pre_edit: string)
--- @param should_cancel? fun(): boolean returns true when the request is stale
function M.get_complete_items_async(callback, should_cancel)
  should_cancel = should_cancel or function()
    return false
  end

  local cursor_pos = vim.api.nvim_win_get_cursor(0)
  local cursor_line = cursor_pos[1]
  local cursor_col = cursor_pos[2]

  -- Deliver an empty result without touching the cache.
  local function bail()
    callback({}, "")
  end

  if should_cancel() then
    return bail()
  end

  request_async("getPrefix", function(raw_prefix)
    local prefix = raw_prefix or ""
    -- Empty prefix means skkeleton is not in input state, so there can be no
    -- candidates. Return empty instead of falling back to extracting pre_edit
    -- from the buffer, which would mix a buffer-derived reading with live-state
    -- candidates.
    if prefix == "" or should_cancel() then
      return bail()
    end

    request_async("getPreEdit", function(raw_pre_edit)
      if should_cancel() then
        return bail()
      end
      -- Use the raw pre_edit (no buffer fallback): with a non-empty prefix,
      -- toString() is guaranteed non-empty ("▽…").
      local pre_edit = raw_pre_edit or ""

      local cached_data = lookup_cache(pre_edit, cursor_line, cursor_col)
      if cached_data then
        callback(cached_data.items, cached_data.pre_edit)
        return
      end

      -- Re-read the prefix once everything has been fetched. If it no longer
      -- matches the prefix we started from, skkeleton's henkanFeed changed
      -- mid-fetch, so pre_edit and the items may be from different states and
      -- must not be shown together. Only on a stable prefix do we filter, cache
      -- and deliver.
      local function finalize(items)
        request_async("getPrefix", function(raw_prefix2)
          if should_cancel() then
            return bail()
          end
          if (raw_prefix2 or "") ~= prefix then
            utils.debug_log(
              string.format("Prefix changed mid-fetch ('%s' -> '%s'), discarding", prefix, raw_prefix2 or "")
            )
            return bail()
          end
          local filtered = filter_items_by_prefix(items, prefix)
          store_cache(pre_edit, filtered, cursor_line, cursor_col)
          utils.debug_log(string.format("pre_edit='%s', items=%d", pre_edit, #filtered))
          callback(filtered, pre_edit)
        end, bail)
      end

      utils.debug_log(string.format("Cache MISS for '%s', fetching (async)...", pre_edit))
      request_async("getCompleteItems", function(raw_items)
        if should_cancel() then
          return bail()
        end
        finalize(decode_items(raw_items or {}))
      end, function()
        callback({}, pre_edit)
      end)
    end, function()
      callback({}, "")
    end)
  end, function()
    callback({}, "")
  end)
end

--- Register completion result with skkeleton for dictionary learning
--- @param kana string
--- @param word string
--- @param henkan_type "okuriari"|"okurinasi"
--- @param inserted string|nil what has been inserted into the buffer, which
---   lets skkeleton take the confirmation back with its kakutei undo. An older
---   skkeleton ignores it.
function M.register_completion(kana, word, henkan_type, inserted)
  utils.debug_log(string.format("register: kana=%s, word=%s, type=%s", kana, word, henkan_type))
  request("completeCallback", { kana, word, henkan_type, inserted or "" })

  -- Clear cache after dictionary learning (ranks may change)
  M.clear_cache()
end

return M
