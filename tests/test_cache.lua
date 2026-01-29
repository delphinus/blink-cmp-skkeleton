--- Tests for blink-cmp-skkeleton.cache module
--- Run with: just test

local new_set = MiniTest.new_set
local expect = MiniTest.expect

local cache_module = require("blink-cmp-skkeleton.cache")

local T = new_set()

-- new() tests
T["new"] = new_set()

T["new"]["creates cache instance with default TTL"] = function()
  local cache = cache_module.new()
  expect.equality(cache.get_ttl(), 100) -- default TTL
end

T["new"]["creates cache instance with custom TTL"] = function()
  local cache = cache_module.new({ ttl_ms = 50 })
  expect.equality(cache.get_ttl(), 50)
end

T["new"]["respects vim.g.blink_cmp_skkeleton_cache_ttl"] = function()
  local old_g = vim.g.blink_cmp_skkeleton_cache_ttl
  vim.g.blink_cmp_skkeleton_cache_ttl = 200
  local cache = cache_module.new()
  expect.equality(cache.get_ttl(), 200)
  vim.g.blink_cmp_skkeleton_cache_ttl = old_g
end

-- is_valid tests
T["is_valid"] = new_set()

T["is_valid"]["returns false for empty cache"] = function()
  local cache = cache_module.new()
  expect.equality(cache.is_valid("test"), false)
end

T["is_valid"]["returns false for different key"] = function()
  local cache = cache_module.new()
  cache.set("key1", "data")
  expect.equality(cache.is_valid("key2"), false)
end

T["is_valid"]["returns true for same key within TTL"] = function()
  local cache = cache_module.new({ ttl_ms = 100 })
  cache.set("key", "data")
  expect.equality(cache.is_valid("key"), true)
end

T["is_valid"]["returns false when TTL expired"] = function()
  local old_loop = vim.loop
  local current_time = 0
  vim.loop = {
    now = function()
      return current_time
    end,
  }

  local cache = cache_module.new({ ttl_ms = 100 })

  current_time = 0
  cache.set("key", "data")

  current_time = 100 -- exactly at TTL boundary
  expect.equality(cache.is_valid("key"), false)

  vim.loop = old_loop
end

-- get/set tests
T["get and set"] = new_set()

T["get and set"]["returns nil for cache miss"] = function()
  local cache = cache_module.new()
  local data, meta = cache.get("nonexistent")
  expect.equality(data, nil)
  expect.equality(meta, nil)
end

T["get and set"]["returns data for cache hit"] = function()
  local cache = cache_module.new()
  cache.set("key", { value = "test" })
  local data, meta = cache.get("key")
  expect.equality(data.value, "test")
end

T["get and set"]["stores and retrieves metadata"] = function()
  local cache = cache_module.new()
  cache.set("key", "data", { cursor_pos = { 1, 5 } })
  local data, meta = cache.get("key")
  expect.equality(data, "data")
  expect.equality(meta.cursor_pos[1], 1)
  expect.equality(meta.cursor_pos[2], 5)
end

-- clear tests
T["clear"] = new_set()

T["clear"]["clears cache data"] = function()
  local cache = cache_module.new()
  cache.set("key", "data")
  cache.clear()
  local data = cache.get("key")
  expect.equality(data, nil)
end

T["clear"]["resets statistics"] = function()
  local cache = cache_module.new()
  cache.set("key", "data")
  cache.get("key") -- hit
  cache.get("key") -- hit
  local stats_before = cache.get_stats()
  expect.equality(stats_before.hits, 2)

  cache.clear()
  local stats_after = cache.get_stats()
  expect.equality(stats_after.hits, 0)
  expect.equality(stats_after.misses, 0)
end

-- get_stats tests
T["get_stats"] = new_set()

T["get_stats"]["tracks hits and misses"] = function()
  local cache = cache_module.new()

  cache.set("key", "data") -- miss (1)
  cache.get("key") -- hit (1)
  cache.get("key") -- hit (2)

  local stats = cache.get_stats()
  expect.equality(stats.hits, 2)
  expect.equality(stats.misses, 1)
end

T["get_stats"]["calculates hit rate correctly"] = function()
  local cache = cache_module.new()

  cache.set("key", "data") -- miss
  cache.get("key") -- hit
  cache.get("key") -- hit
  cache.get("key") -- hit

  local stats = cache.get_stats()
  -- 3 hits, 1 miss = 75% hit rate
  expect.equality(stats.hit_rate >= 74 and stats.hit_rate <= 76, true)
end

T["get_stats"]["returns 0 hit rate for empty cache"] = function()
  local cache = cache_module.new()
  local stats = cache.get_stats()
  expect.equality(stats.hit_rate, 0)
end

-- TTL boundary tests
T["TTL boundary"] = new_set()

T["TTL boundary"]["cache hit just before TTL"] = function()
  local old_loop = vim.loop
  local current_time = 0
  vim.loop = {
    now = function()
      return current_time
    end,
  }

  local cache = cache_module.new({ ttl_ms = 100 })

  current_time = 0
  cache.set("key", "data")

  -- At t=99 (1ms before TTL expires)
  current_time = 99
  local data = cache.get("key")
  expect.equality(data, "data")

  vim.loop = old_loop
end

T["TTL boundary"]["cache miss at exact TTL"] = function()
  local old_loop = vim.loop
  local current_time = 0
  vim.loop = {
    now = function()
      return current_time
    end,
  }

  local cache = cache_module.new({ ttl_ms = 100 })

  current_time = 0
  cache.set("key", "data")

  -- At t=100 (exactly at TTL)
  current_time = 100
  local data = cache.get("key")
  expect.equality(data, nil)

  vim.loop = old_loop
end

-- get_state tests
T["get_state"] = new_set()

T["get_state"]["returns current cache state"] = function()
  local old_loop = vim.loop
  vim.loop = {
    now = function()
      return 12345
    end,
  }

  local cache = cache_module.new()
  cache.set("mykey", "mydata", { extra = "info" })

  local state = cache.get_state()
  expect.equality(state.key, "mykey")
  expect.equality(state.timestamp, 12345)
  expect.equality(state.meta.extra, "info")

  vim.loop = old_loop
end

return T
