--- Tests for blink-cmp-skkeleton.skkeleton module
--- Run with: just test

local new_set = MiniTest.new_set
local expect = MiniTest.expect

local skkeleton = require("blink-cmp-skkeleton.skkeleton")

local T = new_set()

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

-- get_completion_data tests
T["get_completion_data"] = new_set()

T["get_completion_data"]["returns completion data"] = function()
  local old_fn = vim.fn
  vim.fn = setmetatable({}, {
    __index = function(t, k)
      if k == "denops#request" then
        return function(plugin, method, args)
          if method == "getCompletionResult" then
            return { { "あい", { "愛", "藍" } } }
          elseif method == "getRanks" then
            return { { "愛", 100 } }
          elseif method == "getPreEdit" then
            return "▽あい"
          end
        end
      end
      return old_fn[k]
    end,
  })

  local candidates, ranks_array, pre_edit = skkeleton.get_completion_data()

  expect.equality(#candidates, 1)
  expect.equality(candidates[1][1], "あい")
  expect.equality(#ranks_array, 1)
  expect.equality(ranks_array[1][1], "愛")
  expect.equality(pre_edit, "▽あい")

  vim.fn = old_fn
end

T["get_completion_data"]["returns empty data on error"] = function()
  skkeleton.clear_cache()
  local old_fn = vim.fn
  vim.fn = setmetatable({}, {
    __index = function(t, k)
      if k == "denops#request" then
        return function()
          error("test error")
        end
      end
      return old_fn[k]
    end,
  })

  local candidates, ranks_array, pre_edit = skkeleton.get_completion_data()

  expect.equality(type(candidates), "table")
  expect.equality(#candidates, 0)
  expect.equality(type(ranks_array), "table")
  expect.equality(#ranks_array, 0)
  expect.equality(pre_edit, "")

  vim.fn = old_fn
end

-- Cache tests
T["get_completion_data cache"] = new_set()

T["get_completion_data cache"]["caches result for same pre_edit"] = function()
  skkeleton.clear_cache()
  local old_fn = vim.fn
  local denops_call_count = 0

  vim.fn = setmetatable({}, {
    __index = function(t, k)
      if k == "denops#request" then
        return function(plugin, method, args)
          denops_call_count = denops_call_count + 1
          if method == "getCompletionResult" then
            return { { "あい", { "愛", "藍" } } }
          elseif method == "getRanks" then
            return { { "愛", 100 } }
          elseif method == "getPreEdit" then
            return "▽あい"
          end
        end
      end
      return old_fn[k]
    end,
  })

  -- First call: cache miss (3 RPC calls)
  denops_call_count = 0
  local c1, r1, p1 = skkeleton.get_completion_data()
  local first_call_count = denops_call_count
  expect.equality(first_call_count, 3) -- getPreEdit + getCompletionResult + getRanks

  -- Second call: cache hit (only 1 RPC call - getPreEdit to check key)
  denops_call_count = 0
  local c2, r2, p2 = skkeleton.get_completion_data()
  local second_call_count = denops_call_count
  expect.equality(second_call_count, 1) -- only getPreEdit

  -- Data should be same
  expect.equality(#c1, #c2)
  expect.equality(p1, p2)

  vim.fn = old_fn
  skkeleton.clear_cache()
end

T["get_completion_data cache"]["invalidates cache on pre_edit change"] = function()
  local old_fn = vim.fn
  local pre_edit_value = "▽あい"

  vim.fn = setmetatable({}, {
    __index = function(t, k)
      if k == "denops#request" then
        return function(plugin, method, args)
          if method == "getPreEdit" then
            return pre_edit_value
          elseif method == "getCompletionResult" then
            return { { pre_edit_value:sub(4), { "test" } } }
          elseif method == "getRanks" then
            return {}
          end
        end
      end
      return old_fn[k]
    end,
  })

  -- First call
  local c1, r1, p1 = skkeleton.get_completion_data()
  expect.equality(p1, "▽あい")

  -- Change pre_edit
  pre_edit_value = "▽あいう"

  -- Second call: cache miss (different pre_edit)
  local c2, r2, p2 = skkeleton.get_completion_data()
  expect.equality(p2, "▽あいう")
  expect.no_equality(p1, p2)

  vim.fn = old_fn
  skkeleton.clear_cache()
end

T["get_completion_data cache"]["clears cache after register_completion"] = function()
  local old_fn = vim.fn
  local denops_call_count = 0

  vim.fn = setmetatable({}, {
    __index = function(t, k)
      if k == "denops#request" then
        return function(plugin, method, args)
          if method ~= "completeCallback" then
            denops_call_count = denops_call_count + 1
          end
          if method == "getPreEdit" then
            return "▽あい"
          elseif method == "getCompletionResult" then
            return { { "あい", { "愛" } } }
          elseif method == "getRanks" then
            return { { "愛", 100 } }
          end
        end
      end
      return old_fn[k]
    end,
  })

  -- Populate cache
  denops_call_count = 0
  skkeleton.get_completion_data()
  expect.equality(denops_call_count, 3)

  -- Verify cache works
  denops_call_count = 0
  skkeleton.get_completion_data()
  expect.equality(denops_call_count, 1) -- cache hit

  -- Register completion (should clear cache)
  skkeleton.register_completion("あい", "愛", "okurinasi")

  -- Next call should be cache miss
  denops_call_count = 0
  skkeleton.get_completion_data()
  expect.equality(denops_call_count, 3) -- cache was cleared

  vim.fn = old_fn
  skkeleton.clear_cache()
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

-- Cache configuration tests
T["cache configuration"] = new_set()

T["cache configuration"]["uses custom TTL from vim.g"] = function()
  local old_fn = vim.fn
  local old_g = vim.g.blink_cmp_skkeleton_cache_ttl
  local old_loop = vim.loop

  -- Set custom TTL to 50ms
  vim.g.blink_cmp_skkeleton_cache_ttl = 50

  local current_time = 0
  vim.loop = {
    now = function()
      return current_time
    end,
  }

  vim.fn = setmetatable({}, {
    __index = function(t, k)
      if k == "denops#request" then
        return function(plugin, method, args)
          if method == "getPreEdit" then
            return "▽あい"
          elseif method == "getCompletionResult" then
            return { { "あい", { "愛" } } }
          elseif method == "getRanks" then
            return {}
          end
        end
      end
      return old_fn[k]
    end,
  })

  -- First call at t=0
  current_time = 0
  skkeleton.clear_cache()
  skkeleton.get_completion_data()

  -- After 40ms (within 50ms TTL) - should be cache hit
  current_time = 40
  local c1, r1, p1 = skkeleton.get_completion_data()
  expect.equality(p1, "▽あい") -- Should use cache

  -- After 60ms (beyond 50ms TTL) - should be cache miss
  current_time = 60
  local c2, r2, p2 = skkeleton.get_completion_data()
  expect.equality(p2, "▽あい") -- Should refetch

  vim.fn = old_fn
  vim.loop = old_loop
  vim.g.blink_cmp_skkeleton_cache_ttl = old_g
  skkeleton.clear_cache()
end

-- Cache metrics tests
T["cache metrics"] = new_set()

T["cache metrics"]["tracks hit and miss counts"] = function()
  local old_fn = vim.fn

  vim.fn = setmetatable({}, {
    __index = function(t, k)
      if k == "denops#request" then
        return function(plugin, method, args)
          if method == "getPreEdit" then
            return "▽あい"
          elseif method == "getCompletionResult" then
            return { { "あい", { "愛" } } }
          elseif method == "getRanks" then
            return {}
          end
        end
      end
      return old_fn[k]
    end,
  })

  skkeleton.clear_cache()
  local stats = skkeleton.get_cache_stats()
  local initial_hits = stats.hits
  local initial_misses = stats.misses

  -- First call: miss
  skkeleton.get_completion_data()
  stats = skkeleton.get_cache_stats()
  expect.equality(stats.misses, initial_misses + 1)

  -- Second call: hit
  skkeleton.get_completion_data()
  stats = skkeleton.get_cache_stats()
  expect.equality(stats.hits, initial_hits + 1)

  vim.fn = old_fn
  skkeleton.clear_cache()
end

T["cache metrics"]["calculates hit rate correctly"] = function()
  local old_fn = vim.fn

  vim.fn = setmetatable({}, {
    __index = function(t, k)
      if k == "denops#request" then
        return function(plugin, method, args)
          if method == "getPreEdit" then
            return "▽あい"
          elseif method == "getCompletionResult" then
            return { { "あい", { "愛" } } }
          elseif method == "getRanks" then
            return {}
          end
        end
      end
      return old_fn[k]
    end,
  })

  skkeleton.clear_cache()

  -- 1 miss + 3 hits = 75% hit rate
  skkeleton.get_completion_data() -- miss
  skkeleton.get_completion_data() -- hit
  skkeleton.get_completion_data() -- hit
  skkeleton.get_completion_data() -- hit

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

  local denops_call_count = 0
  vim.fn = setmetatable({}, {
    __index = function(t, k)
      if k == "denops#request" then
        return function(plugin, method, args)
          denops_call_count = denops_call_count + 1
          if method == "getPreEdit" then
            return "▽あい"
          elseif method == "getCompletionResult" then
            return { { "あい", { "愛" } } }
          elseif method == "getRanks" then
            return {}
          end
        end
      end
      return old_fn[k]
    end,
  })

  -- First call at t=0 (cache miss)
  current_time = 0
  skkeleton.clear_cache()
  denops_call_count = 0
  skkeleton.get_completion_data()
  expect.equality(denops_call_count, 3) -- miss: getPreEdit + getCompletionResult + getRanks

  -- At t=99 (just before 100ms TTL) - should be cache hit
  current_time = 99
  denops_call_count = 0
  skkeleton.get_completion_data()
  expect.equality(denops_call_count, 1) -- hit: only getPreEdit

  -- At t=100 (exactly at 100ms TTL) - should be cache miss
  current_time = 100
  denops_call_count = 0
  skkeleton.get_completion_data()
  expect.equality(denops_call_count, 3) -- miss: full fetch

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

  local denops_call_count = 0
  vim.fn = setmetatable({}, {
    __index = function(t, k)
      if k == "denops#request" then
        return function(plugin, method, args)
          denops_call_count = denops_call_count + 1
          if method == "getPreEdit" then
            return "▽あい"
          elseif method == "getCompletionResult" then
            return { { "あい", { "愛" } } }
          elseif method == "getRanks" then
            return {}
          end
        end
      end
      return old_fn[k]
    end,
  })

  -- First call at t=0 (cache miss)
  current_time = 0
  skkeleton.clear_cache()
  denops_call_count = 0
  skkeleton.get_completion_data()
  expect.equality(denops_call_count, 3) -- miss

  -- At t=50 (half of 100ms TTL) - should be cache hit
  current_time = 50
  denops_call_count = 0
  skkeleton.get_completion_data()
  expect.equality(denops_call_count, 1) -- hit

  -- At t=99 (1ms before TTL) - should still be cache hit
  current_time = 99
  denops_call_count = 0
  skkeleton.get_completion_data()
  expect.equality(denops_call_count, 1) -- hit

  vim.fn = old_fn
  vim.loop = old_loop
  skkeleton.clear_cache()
end

-- get_completion_data_async tests
T["get_completion_data_async"] = new_set()

--- Build a vim.fn mock whose denops#request_async resolves each method via the
--- success callback. `counter` (optional) is incremented per async RPC.
local function mock_async(old_fn, responses, counter)
  return setmetatable({}, {
    __index = function(_, k)
      if k == "denops#request_async" then
        return function(_plugin, method, _args, success, _failure)
          if counter then
            counter.count = counter.count + 1
          end
          success(responses[method])
        end
      end
      return old_fn[k]
    end,
  })
end

T["get_completion_data_async"]["returns completion data"] = function()
  skkeleton.clear_cache()
  local old_fn = vim.fn
  vim.fn = mock_async(old_fn, {
    getPreEdit = "▽あい",
    getCompletionResult = { { "あい", { "愛", "藍" } } },
    getRanks = { { "愛", 100 } },
  })

  local result
  skkeleton.get_completion_data_async(function(candidates, ranks_array, pre_edit)
    result = { candidates = candidates, ranks_array = ranks_array, pre_edit = pre_edit }
  end)

  expect.no_equality(result, nil)
  expect.equality(#result.candidates, 1)
  expect.equality(result.candidates[1][1], "あい")
  expect.equality(result.ranks_array[1][1], "愛")
  expect.equality(result.pre_edit, "▽あい")

  vim.fn = old_fn
  skkeleton.clear_cache()
end

T["get_completion_data_async"]["returns empty data on failure"] = function()
  skkeleton.clear_cache()
  local old_fn = vim.fn
  vim.fn = setmetatable({}, {
    __index = function(_, k)
      if k == "denops#request_async" then
        return function(_plugin, method, _args, success, failure)
          if method == "getPreEdit" then
            success("▽あい")
          else
            -- getCompletionResult fails
            failure("boom")
          end
        end
      end
      return old_fn[k]
    end,
  })

  local result
  skkeleton.get_completion_data_async(function(candidates, ranks_array, pre_edit)
    result = { candidates = candidates, ranks_array = ranks_array, pre_edit = pre_edit }
  end)

  expect.no_equality(result, nil)
  expect.equality(#result.candidates, 0)
  expect.equality(#result.ranks_array, 0)
  expect.equality(result.pre_edit, "▽あい")

  vim.fn = old_fn
  skkeleton.clear_cache()
end

T["get_completion_data_async"]["caches result for same pre_edit"] = function()
  skkeleton.clear_cache()
  local old_fn = vim.fn
  local counter = { count = 0 }
  vim.fn = mock_async(old_fn, {
    getPreEdit = "▽あい",
    getCompletionResult = { { "あい", { "愛" } } },
    getRanks = { { "愛", 100 } },
  }, counter)

  -- First call: cache miss (getPreEdit + getCompletionResult + getRanks)
  counter.count = 0
  skkeleton.get_completion_data_async(function() end)
  expect.equality(counter.count, 3)

  -- Second call: cache hit (only getPreEdit to check the key)
  counter.count = 0
  skkeleton.get_completion_data_async(function() end)
  expect.equality(counter.count, 1)

  vim.fn = old_fn
  skkeleton.clear_cache()
end

return T
