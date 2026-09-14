--- Tests for blink-cmp-skkeleton.skkeleton module
--- Run with: just test

local new_set = MiniTest.new_set
local expect = MiniTest.expect

local skkeleton = require("blink-cmp-skkeleton.skkeleton")

local T = new_set()

--- Build a vim.fn mock whose denops#request_async resolves each method via the
--- success callback. `counter` (optional) is incremented per async RPC.
--- When `responses.getPrefix` is omitted it defaults to the getPreEdit value
--- with the leading ▽ marker stripped (= the henkanFeed), so existing fixtures
--- keep working with the prefix-anchored async flow.
local function mock_async(old_fn, responses, counter)
  return setmetatable({}, {
    __index = function(_, k)
      if k == "denops#request_async" then
        return function(_plugin, method, _args, success, _failure)
          if counter then
            counter.count = counter.count + 1
          end
          local value = responses[method]
          if method == "getPrefix" and value == nil then
            value = (responses.getPreEdit or ""):gsub("^▽", "")
          end
          success(value)
        end
      end
      return old_fn[k]
    end,
  })
end

--- Build one getCompleteItems entry the way skkeleton sends it over denops:
--- everything the source needs at confirm time rides along as JSON in
--- user_data.
--- @param word string text to insert (okurigana included for okuriari)
--- @param midasi string midashi the candidate was looked up under
--- @param candidate string raw candidate, annotation included
--- @param henkan_type? "okurinasi"|"okuriari" defaults to "okurinasi"
--- @param info? string annotation
local function raw_item(word, midasi, candidate, henkan_type, info)
  return {
    word = word,
    abbr = word,
    info = info or "",
    equal = 1,
    dup = 1,
    empty = 1,
    user_data = vim.json.encode({
      tag = "skkeleton",
      midasi = midasi,
      word = candidate,
      type = henkan_type or "okurinasi",
    }),
  }
end

-- is_enabled tests
T["is_enabled"] = new_set()

T["is_enabled"]["returns true when skkeleton is enabled"] = function()
  local old_fn = vim.fn
  vim.fn = setmetatable({}, {
    __index = function(t, k)
      if k == "skkeleton#is_enabled" then
        return function()
          return 1
        end
      end
      return old_fn[k]
    end,
  })

  local result = skkeleton.is_enabled()
  expect.equality(result, true)

  vim.fn = old_fn
end

T["is_enabled"]["returns false when skkeleton is disabled"] = function()
  local old_fn = vim.fn
  vim.fn = setmetatable({}, {
    __index = function(t, k)
      if k == "skkeleton#is_enabled" then
        return function()
          return 0
        end
      end
      return old_fn[k]
    end,
  })

  local result = skkeleton.is_enabled()
  expect.equality(result, false)

  vim.fn = old_fn
end

T["is_enabled"]["returns false on error"] = function()
  local old_fn = vim.fn
  vim.fn = setmetatable({}, {
    __index = function(t, k)
      if k == "skkeleton#is_enabled" then
        return function()
          error("test error")
        end
      end
      return old_fn[k]
    end,
  })

  local result = skkeleton.is_enabled()
  expect.equality(result, false)

  vim.fn = old_fn
end

-- register_completion tests
T["register_completion"] = new_set()

T["register_completion"]["calls denops request"] = function()
  local old_fn = vim.fn
  local called = false
  local call_args = nil

  vim.fn = setmetatable({}, {
    __index = function(t, k)
      if k == "denops#request" then
        return function(plugin, method, args)
          if method == "completeCallback" then
            called = true
            call_args = args
          end
        end
      end
      return old_fn[k]
    end,
  })

  skkeleton.register_completion("あい", "愛", "okurinasi")

  expect.equality(called, true)
  expect.equality(call_args[1], "あい")
  expect.equality(call_args[2], "愛")
  expect.equality(call_args[3], "okurinasi")

  vim.fn = old_fn
  skkeleton.clear_cache()
end

-- get_complete_items_async tests
T["get_complete_items_async"] = new_set()

T["get_complete_items_async"]["returns complete items"] = function()
  skkeleton.clear_cache()
  local old_fn = vim.fn
  vim.fn = mock_async(old_fn, {
    getPreEdit = "▽あい",
    getCompleteItems = {
      raw_item("愛", "あい", "愛"),
      raw_item("藍", "あい", "藍;indigo", "okurinasi", "indigo"),
    },
  })

  local result
  skkeleton.get_complete_items_async(function(items, pre_edit)
    result = { items = items, pre_edit = pre_edit }
  end)

  expect.no_equality(result, nil)
  expect.equality(#result.items, 2)
  expect.equality(result.items[1].word, "愛")
  expect.equality(result.items[1].midasi, "あい")
  expect.equality(result.items[1].henkan_type, "okurinasi")
  expect.equality(result.items[2].candidate, "藍;indigo")
  expect.equality(result.items[2].info, "indigo")
  expect.equality(result.pre_edit, "▽あい")

  vim.fn = old_fn
  skkeleton.clear_cache()
end

T["get_complete_items_async"]["returns okuriari items alongside okurinasi ones"] = function()
  skkeleton.clear_cache()
  local old_fn = vim.fn
  vim.fn = mock_async(old_fn, {
    getPreEdit = "▽あたり",
    getCompleteItems = {
      raw_item("辺り", "あたり", "辺り"),
      -- 読みを「あた」+「り」に分けて引いた候補。word は送り仮名込み
      raw_item("当たり", "あたr", "当た", "okuriari"),
    },
  })

  local result
  skkeleton.get_complete_items_async(function(items)
    result = items
  end)

  expect.equality(#result, 2)
  expect.equality(result[2].word, "当たり")
  expect.equality(result[2].midasi, "あたr")
  expect.equality(result[2].candidate, "当た")
  expect.equality(result[2].henkan_type, "okuriari")

  vim.fn = old_fn
  skkeleton.clear_cache()
end

T["get_complete_items_async"]["drops items with unusable user_data"] = function()
  skkeleton.clear_cache()
  local old_fn = vim.fn
  vim.fn = mock_async(old_fn, {
    getPreEdit = "▽あい",
    getCompleteItems = {
      raw_item("愛", "あい", "愛"),
      { word = "藍", user_data = "not json" },
      { word = "哀", user_data = vim.json.encode({ tag = "other-plugin" }) },
      { word = "相" },
    },
  })

  local result
  skkeleton.get_complete_items_async(function(items)
    result = items
  end)

  expect.equality(#result, 1)
  expect.equality(result[1].word, "愛")

  vim.fn = old_fn
  skkeleton.clear_cache()
end

T["get_complete_items_async"]["returns empty data on failure"] = function()
  skkeleton.clear_cache()
  local old_fn = vim.fn
  vim.fn = setmetatable({}, {
    __index = function(_, k)
      if k == "denops#request_async" then
        return function(_plugin, method, _args, success, failure)
          if method == "getPrefix" then
            success("あい")
          elseif method == "getPreEdit" then
            success("▽あい")
          else
            -- getCompleteItems fails
            failure("boom")
          end
        end
      end
      return old_fn[k]
    end,
  })

  local result
  skkeleton.get_complete_items_async(function(items, pre_edit)
    result = { items = items, pre_edit = pre_edit }
  end)

  expect.no_equality(result, nil)
  expect.equality(#result.items, 0)
  expect.equality(result.pre_edit, "▽あい")

  vim.fn = old_fn
  skkeleton.clear_cache()
end

T["get_complete_items_async"]["caches result for same pre_edit"] = function()
  skkeleton.clear_cache()
  local old_fn = vim.fn
  local counter = { count = 0 }
  vim.fn = mock_async(old_fn, {
    getPreEdit = "▽あい",
    getCompleteItems = { raw_item("愛", "あい", "愛") },
  }, counter)

  -- First call: cache miss
  -- (getPrefix + getPreEdit + getCompleteItems + getPrefix re-check)
  counter.count = 0
  skkeleton.get_complete_items_async(function() end)
  expect.equality(counter.count, 4)

  -- Second call: cache hit (getPrefix + getPreEdit to check the key)
  counter.count = 0
  skkeleton.get_complete_items_async(function() end)
  expect.equality(counter.count, 2)

  vim.fn = old_fn
  skkeleton.clear_cache()
end

T["get_complete_items_async"]["invalidates cache on pre_edit change"] = function()
  skkeleton.clear_cache()
  local old_fn = vim.fn
  local pre_edit_value = "▽あい"

  vim.fn = setmetatable({}, {
    __index = function(_, k)
      if k == "denops#request_async" then
        return function(_plugin, method, _args, success, _failure)
          if method == "getPrefix" then
            success((pre_edit_value:gsub("^▽", "")))
          elseif method == "getPreEdit" then
            success(pre_edit_value)
          elseif method == "getCompleteItems" then
            success({ raw_item("test", pre_edit_value:sub(4), "test") })
          else
            success(nil)
          end
        end
      end
      return old_fn[k]
    end,
  })

  -- First call
  local p1
  skkeleton.get_complete_items_async(function(_items, pre_edit)
    p1 = pre_edit
  end)
  expect.equality(p1, "▽あい")

  -- Change pre_edit
  pre_edit_value = "▽あいう"

  -- Second call: cache miss (different pre_edit)
  local p2
  skkeleton.get_complete_items_async(function(_items, pre_edit)
    p2 = pre_edit
  end)
  expect.equality(p2, "▽あいう")
  expect.no_equality(p1, p2)

  vim.fn = old_fn
  skkeleton.clear_cache()
end

T["get_complete_items_async"]["clears cache after register_completion"] = function()
  skkeleton.clear_cache()
  local old_fn = vim.fn
  local counter = { count = 0 }
  -- register_completion issues completeCallback via the synchronous denops#request,
  -- which this mock leaves to old_fn (pcall-guarded, so it is a harmless no-op in
  -- tests) and does not count -- only async RPCs increment the counter.
  vim.fn = mock_async(old_fn, {
    getPreEdit = "▽あい",
    getCompleteItems = { raw_item("愛", "あい", "愛") },
  }, counter)

  -- Populate cache
  counter.count = 0
  skkeleton.get_complete_items_async(function() end)
  expect.equality(counter.count, 4)

  -- Verify cache works
  counter.count = 0
  skkeleton.get_complete_items_async(function() end)
  expect.equality(counter.count, 2) -- cache hit

  -- Register completion (should clear cache)
  skkeleton.register_completion("あい", "愛", "okurinasi")

  -- Next call should be cache miss
  counter.count = 0
  skkeleton.get_complete_items_async(function() end)
  expect.equality(counter.count, 4) -- cache was cleared

  vim.fn = old_fn
  skkeleton.clear_cache()
end

T["get_complete_items_async"]["drops candidates whose midashi does not match the prefix"] = function()
  skkeleton.clear_cache()
  local old_fn = vim.fn
  vim.fn = mock_async(old_fn, {
    getPrefix = "あい",
    getPreEdit = "▽あい",
    getCompleteItems = {
      raw_item("愛", "あい", "愛"),
      -- "じぇい" は prefix "あい" に前方一致しないので除去される
      raw_item("J POINTS", "じぇい", "J POINTS"),
    },
  })

  local result
  skkeleton.get_complete_items_async(function(items, pre_edit)
    result = { items = items, pre_edit = pre_edit }
  end)

  expect.no_equality(result, nil)
  expect.equality(#result.items, 1)
  expect.equality(result.items[1].midasi, "あい")
  expect.equality(result.pre_edit, "▽あい")

  vim.fn = old_fn
  skkeleton.clear_cache()
end

T["get_complete_items_async"]["keeps okuriari items cut at the okurigana"] = function()
  skkeleton.clear_cache()
  local old_fn = vim.fn
  vim.fn = mock_async(old_fn, {
    getPrefix = "あたり",
    getPreEdit = "▽あたり",
    getCompleteItems = {
      -- 送りありの見出しは読みを送り仮名で切ったもの ("あた" + "り" の頭文字)
      raw_item("当たり", "あたr", "当た", "okuriari"),
      -- "おく" は読み "あたり" の先頭ではないので除去される
      raw_item("送り", "おくr", "送", "okuriari"),
    },
  })

  local result
  skkeleton.get_complete_items_async(function(items)
    result = items
  end)

  expect.equality(#result, 1)
  expect.equality(result[1].midasi, "あたr")

  vim.fn = old_fn
  skkeleton.clear_cache()
end

T["get_complete_items_async"]["discards result when prefix changes mid-fetch"] = function()
  skkeleton.clear_cache()
  local old_fn = vim.fn
  -- getPrefix is read twice: once up front, once after the items. Return a
  -- different henkanFeed the second time to simulate a keystroke landing
  -- mid-fetch. The reading/candidates are then from inconsistent states and the
  -- whole result must be dropped.
  local prefix_calls = 0
  vim.fn = setmetatable({}, {
    __index = function(_, k)
      if k == "denops#request_async" then
        return function(_plugin, method, _args, success, _failure)
          if method == "getPrefix" then
            prefix_calls = prefix_calls + 1
            success(prefix_calls == 1 and "あい" or "あいう")
          elseif method == "getPreEdit" then
            success("▽あい")
          elseif method == "getCompleteItems" then
            success({ raw_item("愛", "あい", "愛") })
          else
            success(nil)
          end
        end
      end
      return old_fn[k]
    end,
  })

  local result
  skkeleton.get_complete_items_async(function(items, pre_edit)
    result = { items = items, pre_edit = pre_edit }
  end)

  expect.no_equality(result, nil)
  expect.equality(#result.items, 0)
  expect.equality(result.pre_edit, "")
  expect.equality(prefix_calls, 2)

  vim.fn = old_fn
  skkeleton.clear_cache()
end

T["get_complete_items_async"]["returns empty when not in input state"] = function()
  skkeleton.clear_cache()
  local old_fn = vim.fn
  local completion_called = false
  vim.fn = setmetatable({}, {
    __index = function(_, k)
      if k == "denops#request_async" then
        return function(_plugin, method, _args, success, _failure)
          if method == "getPrefix" then
            success("")
          elseif method == "getCompleteItems" then
            completion_called = true
            success({})
          else
            success(nil)
          end
        end
      end
      return old_fn[k]
    end,
  })

  local result
  skkeleton.get_complete_items_async(function(items, pre_edit)
    result = { items = items, pre_edit = pre_edit }
  end)

  expect.no_equality(result, nil)
  expect.equality(#result.items, 0)
  expect.equality(result.pre_edit, "")
  -- empty prefix short-circuits before fetching candidates
  expect.equality(completion_called, false)

  vim.fn = old_fn
  skkeleton.clear_cache()
end

T["get_complete_items_async"]["bails out and skips fetching when cancelled"] = function()
  skkeleton.clear_cache()
  local old_fn = vim.fn
  local counter = { count = 0 }
  vim.fn = mock_async(old_fn, {
    getPrefix = "あい",
    getPreEdit = "▽あい",
    getCompleteItems = { raw_item("愛", "あい", "愛") },
  }, counter)

  local result
  counter.count = 0
  skkeleton.get_complete_items_async(function(items, pre_edit)
    result = { items = items, pre_edit = pre_edit }
  end, function()
    return true
  end)

  expect.no_equality(result, nil)
  expect.equality(#result.items, 0)
  expect.equality(result.pre_edit, "")
  -- cancelled before the first RPC: the chain never issues a request
  expect.equality(counter.count, 0)

  vim.fn = old_fn
  skkeleton.clear_cache()
end

-- Cache configuration tests
T["cache configuration"] = new_set()

T["cache configuration"]["returns data with custom TTL from vim.g"] = function()
  local old_fn = vim.fn
  local old_g = vim.g.blink_cmp_skkeleton_cache_ttl
  local old_loop = vim.loop

  vim.g.blink_cmp_skkeleton_cache_ttl = 50

  local current_time = 0
  vim.loop = {
    now = function()
      return current_time
    end,
  }

  vim.fn = mock_async(old_fn, {
    getPreEdit = "▽あい",
    getCompleteItems = { raw_item("愛", "あい", "愛") },
  })

  local function fetch()
    local pre_edit
    skkeleton.get_complete_items_async(function(_items, p)
      pre_edit = p
    end)
    return pre_edit
  end

  current_time = 0
  skkeleton.clear_cache()
  expect.equality(fetch(), "▽あい")

  current_time = 40
  expect.equality(fetch(), "▽あい")

  current_time = 60
  expect.equality(fetch(), "▽あい")

  vim.fn = old_fn
  vim.loop = old_loop
  vim.g.blink_cmp_skkeleton_cache_ttl = old_g
  skkeleton.clear_cache()
end

-- Cache metrics tests
T["cache metrics"] = new_set()

T["cache metrics"]["tracks hit and miss counts"] = function()
  local old_fn = vim.fn
  vim.fn = mock_async(old_fn, {
    getPreEdit = "▽あい",
    getCompleteItems = { raw_item("愛", "あい", "愛") },
  })

  skkeleton.clear_cache()
  local stats = skkeleton.get_cache_stats()
  local initial_hits = stats.hits
  local initial_misses = stats.misses

  -- First call: miss
  skkeleton.get_complete_items_async(function() end)
  stats = skkeleton.get_cache_stats()
  expect.equality(stats.misses, initial_misses + 1)

  -- Second call: hit
  skkeleton.get_complete_items_async(function() end)
  stats = skkeleton.get_cache_stats()
  expect.equality(stats.hits, initial_hits + 1)

  vim.fn = old_fn
  skkeleton.clear_cache()
end

T["cache metrics"]["calculates hit rate correctly"] = function()
  local old_fn = vim.fn
  vim.fn = mock_async(old_fn, {
    getPreEdit = "▽あい",
    getCompleteItems = { raw_item("愛", "あい", "愛") },
  })

  skkeleton.clear_cache()

  -- 1 miss + 3 hits = 75% hit rate
  skkeleton.get_complete_items_async(function() end) -- miss
  skkeleton.get_complete_items_async(function() end) -- hit
  skkeleton.get_complete_items_async(function() end) -- hit
  skkeleton.get_complete_items_async(function() end) -- hit

  local stats = skkeleton.get_cache_stats()
  expect.equality(stats.hit_rate >= 74 and stats.hit_rate <= 76, true) -- Allow for floating point

  vim.fn = old_fn
  skkeleton.clear_cache()
end

-- TTL boundary tests (uses default 100ms TTL)
T["cache TTL boundary"] = new_set()

T["cache TTL boundary"]["invalidates at exact TTL boundary"] = function()
  local old_fn = vim.fn
  local old_loop = vim.loop

  -- Uses default TTL of 100ms (set at module load time)
  local current_time = 0
  vim.loop = {
    now = function()
      return current_time
    end,
  }

  local counter = { count = 0 }
  vim.fn = mock_async(old_fn, {
    getPreEdit = "▽あい",
    getCompleteItems = { raw_item("愛", "あい", "愛") },
  }, counter)

  -- First call at t=0 (cache miss)
  current_time = 0
  skkeleton.clear_cache()
  counter.count = 0
  skkeleton.get_complete_items_async(function() end)
  expect.equality(counter.count, 4) -- miss: full fetch + prefix re-check

  -- At t=99 (just before 100ms TTL) - should be cache hit
  current_time = 99
  counter.count = 0
  skkeleton.get_complete_items_async(function() end)
  expect.equality(counter.count, 2) -- hit: getPrefix + getPreEdit

  -- At t=100 (exactly at 100ms TTL) - should be cache miss
  current_time = 100
  counter.count = 0
  skkeleton.get_complete_items_async(function() end)
  expect.equality(counter.count, 4) -- miss: full fetch

  vim.fn = old_fn
  vim.loop = old_loop
  skkeleton.clear_cache()
end

T["cache TTL boundary"]["just before TTL is cache hit"] = function()
  local old_fn = vim.fn
  local old_loop = vim.loop

  local current_time = 0
  vim.loop = {
    now = function()
      return current_time
    end,
  }

  local counter = { count = 0 }
  vim.fn = mock_async(old_fn, {
    getPreEdit = "▽あい",
    getCompleteItems = { raw_item("愛", "あい", "愛") },
  }, counter)

  -- First call at t=0 (cache miss)
  current_time = 0
  skkeleton.clear_cache()
  counter.count = 0
  skkeleton.get_complete_items_async(function() end)
  expect.equality(counter.count, 4) -- miss

  -- At t=50 (half of 100ms TTL) - should be cache hit
  current_time = 50
  counter.count = 0
  skkeleton.get_complete_items_async(function() end)
  expect.equality(counter.count, 2) -- hit

  -- At t=99 (1ms before TTL) - should still be cache hit
  current_time = 99
  counter.count = 0
  skkeleton.get_complete_items_async(function() end)
  expect.equality(counter.count, 2) -- hit

  vim.fn = old_fn
  vim.loop = old_loop
  skkeleton.clear_cache()
end

return T
