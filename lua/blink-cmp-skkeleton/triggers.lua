--- Japanese trigger character generation module
--- @module blink-cmp-skkeleton.triggers

local M = {}

--- Generate all hiragana characters as trigger characters
--- @return string[]
function M.generate_hiragana()
  local triggers = {}
  -- Basic hiragana: ぁ-ん (U+3041 - U+3093)
  for codepoint = 0x3041, 0x3093 do
    table.insert(triggers, vim.fn.nr2char(codepoint))
  end
  -- Additional hiragana marks: ゛゜ゝゞ (U+309B - U+309E)
  for codepoint = 0x309B, 0x309E do
    table.insert(triggers, vim.fn.nr2char(codepoint))
  end
  -- Long vowel mark: ー (U+30FC)
  table.insert(triggers, vim.fn.nr2char(0x30FC))
  return triggers
end

--- Generate all katakana characters as trigger characters
--- @return string[]
function M.generate_katakana()
  local triggers = {}
  -- Basic katakana: ァ-ヴ (U+30A1 - U+30F4)
  for codepoint = 0x30A1, 0x30F4 do
    table.insert(triggers, vim.fn.nr2char(codepoint))
  end
  -- Additional katakana marks: ・ヽヾ (U+30FB - U+30FE)
  for codepoint = 0x30FB, 0x30FE do
    table.insert(triggers, vim.fn.nr2char(codepoint))
  end
  return triggers
end

--- Generate all Japanese trigger characters (hiragana + katakana)
--- @return string[]
function M.generate_japanese()
  local triggers = M.generate_hiragana()
  vim.list_extend(triggers, M.generate_katakana())
  return triggers
end

return M
