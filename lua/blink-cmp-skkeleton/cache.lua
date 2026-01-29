--- TTL-based cache management module
--- @module blink-cmp-skkeleton.cache

local M = {}

--- Create a new cache instance
--- @param opts? { ttl_ms: number } Options (ttl_ms defaults to vim.g.blink_cmp_skkeleton_cache_ttl or 100)
--- @return table Cache instance
function M.new(opts)
  opts = opts or {}
  local ttl_ms = opts.ttl_ms or vim.g.blink_cmp_skkeleton_cache_ttl or 100

  local cache = {
    key = nil, -- Cache key
    data = nil, -- Cached data
    timestamp = 0, -- Cache creation time
    meta = nil, -- Additional metadata (e.g., cursor position)
  }

  local stats = {
    hits = 0,
    misses = 0,
  }

  local instance = {}

  --- Check if cache is valid for the given key
  --- @param key string
  --- @return boolean
  function instance.is_valid(key)
    if cache.key ~= key or not cache.data then
      return false
    end

    local now = vim.loop.now()
    local age = now - cache.timestamp

    return age < ttl_ms
  end

  --- Get cached data if valid
  --- @param key string
  --- @return any|nil data, table|nil meta
  function instance.get(key)
    if instance.is_valid(key) then
      stats.hits = stats.hits + 1
      return cache.data, cache.meta
    end
    return nil, nil
  end

  --- Set cache data
  --- @param key string
  --- @param data any
  --- @param meta? table Additional metadata
  function instance.set(key, data, meta)
    cache.key = key
    cache.data = data
    cache.timestamp = vim.loop.now()
    cache.meta = meta
    stats.misses = stats.misses + 1
  end

  --- Clear cache and reset statistics
  function instance.clear()
    cache.key = nil
    cache.data = nil
    cache.timestamp = 0
    cache.meta = nil
    stats.hits = 0
    stats.misses = 0
  end

  --- Get cache statistics
  --- @return table stats { hits: number, misses: number, hit_rate: number }
  function instance.get_stats()
    local total = stats.hits + stats.misses
    return {
      hits = stats.hits,
      misses = stats.misses,
      hit_rate = total > 0 and (stats.hits / total * 100) or 0,
    }
  end

  --- Get current TTL setting
  --- @return number
  function instance.get_ttl()
    return ttl_ms
  end

  --- Get current cache state (for advanced use cases)
  --- @return table { key: string|nil, timestamp: number, meta: table|nil }
  function instance.get_state()
    return {
      key = cache.key,
      timestamp = cache.timestamp,
      meta = cache.meta,
    }
  end

  return instance
end

return M
