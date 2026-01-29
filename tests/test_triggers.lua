--- Tests for blink-cmp-skkeleton.triggers module
--- Run with: just test

local new_set = MiniTest.new_set
local expect = MiniTest.expect

local triggers = require("blink-cmp-skkeleton.triggers")

local T = new_set()

-- generate_hiragana tests
T["generate_hiragana"] = new_set()

T["generate_hiragana"]["generates all basic hiragana characters"] = function()
  local result = triggers.generate_hiragana()
  -- Should include basic hiragana
  expect.equality(vim.tbl_contains(result, "あ"), true)
  expect.equality(vim.tbl_contains(result, "い"), true)
  expect.equality(vim.tbl_contains(result, "ん"), true)
end

T["generate_hiragana"]["includes hiragana marks"] = function()
  local result = triggers.generate_hiragana()
  -- Should include marks
  expect.equality(vim.tbl_contains(result, "゛"), true) -- U+309B
  expect.equality(vim.tbl_contains(result, "゜"), true) -- U+309C
  expect.equality(vim.tbl_contains(result, "ー"), true) -- U+30FC (long vowel mark)
end

T["generate_hiragana"]["generates correct number of characters"] = function()
  local result = triggers.generate_hiragana()
  -- Basic hiragana (U+3041-U+3093): 83 chars
  -- Marks (U+309B-U+309E): 4 chars
  -- Long vowel (U+30FC): 1 char
  -- Total: ~88 chars
  expect.equality(#result >= 85 and #result <= 90, true)
end

-- generate_katakana tests
T["generate_katakana"] = new_set()

T["generate_katakana"]["generates all basic katakana characters"] = function()
  local result = triggers.generate_katakana()
  -- Should include basic katakana
  expect.equality(vim.tbl_contains(result, "ア"), true)
  expect.equality(vim.tbl_contains(result, "イ"), true)
  expect.equality(vim.tbl_contains(result, "ン"), true)
end

T["generate_katakana"]["includes katakana marks"] = function()
  local result = triggers.generate_katakana()
  -- Should include marks
  expect.equality(vim.tbl_contains(result, "・"), true) -- U+30FB
end

T["generate_katakana"]["generates correct number of characters"] = function()
  local result = triggers.generate_katakana()
  -- Basic katakana (U+30A1-U+30F4): 84 chars
  -- Marks (U+30FB-U+30FE): 4 chars
  -- Total: ~88 chars
  expect.equality(#result >= 85 and #result <= 90, true)
end

-- generate_japanese tests
T["generate_japanese"] = new_set()

T["generate_japanese"]["combines hiragana and katakana"] = function()
  local result = triggers.generate_japanese()
  -- Should include both hiragana and katakana
  expect.equality(vim.tbl_contains(result, "あ"), true)
  expect.equality(vim.tbl_contains(result, "ア"), true)
  expect.equality(vim.tbl_contains(result, "ん"), true)
  expect.equality(vim.tbl_contains(result, "ン"), true)
end

T["generate_japanese"]["generates approximately 174 characters"] = function()
  local result = triggers.generate_japanese()
  -- Hiragana (~88) + Katakana (~88) = ~176 chars
  expect.equality(#result >= 170 and #result <= 180, true)
end

return T
