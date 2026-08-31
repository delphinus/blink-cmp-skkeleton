--- Utility functions for blink-cmp-skkeleton
--- @module blink-cmp-skkeleton.utils

local M = {}

--- Open log file, keyed by path so a changed `blink_cmp_skkeleton_debug_file`
--- takes effect without a restart.
--- @type { path: string, handle: file*|nil }|nil
local log_file = nil

--- @param path string
--- @return file*|nil
local function log_handle(path)
  if log_file and log_file.path == path then
    return log_file.handle
  end
  if log_file and log_file.handle then
    log_file.handle:close()
  end
  local handle = io.open(path, "a")
  log_file = { path = path, handle = handle }
  return handle
end

--- Log debug message.
---
--- `vim.g.blink_cmp_skkeleton_debug` sends it to `:messages`, which is awkward
--- to read in a short-lived instance (an editprompt buffer, say). Set
--- `vim.g.blink_cmp_skkeleton_debug_file` to a path to append it there instead
--- or as well. Both may be enabled at once.
--- @param msg string
function M.debug_log(msg)
  if vim.g.blink_cmp_skkeleton_debug then
    vim.notify("[blink-cmp-skkeleton] " .. msg, vim.log.levels.INFO)
  end

  local path = vim.g.blink_cmp_skkeleton_debug_file
  if type(path) ~= "string" or path == "" then
    return
  end
  local handle = log_handle(path)
  if not handle then
    return
  end
  -- The pid keeps concurrent instances sharing a path apart
  handle:write(string.format("%s [%d] %s\n", os.date("%H:%M:%S"), vim.fn.getpid(), msg))
  handle:flush()
end

--- Helper function to safely call vim functions
--- @param fn function|nil
--- @param ... unknown args
--- @return unknown
function M.safe_call(fn, ...)
  if not fn then
    return nil
  end
  local ok, result = pcall(fn, ...)
  return ok and result or nil
end

--- Parse word to extract label and info
--- @param word string
--- @return string label, string info
function M.parse_word(word)
  local label = word:gsub(";.*$", "")
  local info = word:find(";") and word:gsub(".*;", "") or ""
  return label, info
end

--- Determine henkan type from kana string
--- @param kana string
--- @return "okuriari"|"okurinasi"
function M.determine_henkan_type(kana)
  -- If kana contains uppercase letter or asterisk, it's okuriari (送りあり)
  if kana:match("[A-Z]") or kana:match("%*") then
    return "okuriari"
  end
  return "okurinasi"
end

return M
