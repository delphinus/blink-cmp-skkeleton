--- Tests for blink-cmp-skkeleton.completion module
--- Run with: just test

local new_set = MiniTest.new_set
local expect = MiniTest.expect

local completion = require("blink-cmp-skkeleton.completion")

local T = new_set()

local text_edit_range = {
  start = { line = 0, character = 0 },
  ["end"] = { line = 0, character = 9 },
}

--- Build a decoded complete item, the shape skkeleton.lua hands over.
--- @param word string text to insert (okurigana included for okuriari)
--- @param midasi string
--- @param candidate string raw candidate, annotation included
--- @param henkan_type? "okurinasi"|"okuriari" defaults to "okurinasi"
--- @param info? string annotation
--- @param rank? integer completion rank, nil when the candidate is unlearned
local function complete_item(word, midasi, candidate, henkan_type, info, rank)
  return {
    word = word,
    info = info or "",
    midasi = midasi,
    candidate = candidate,
    henkan_type = henkan_type or "okurinasi",
    rank = rank,
  }
end

-- build_completion_item tests
T["build_completion_item"] = new_set()

T["build_completion_item"]["creates item without documentation"] = function()
  local item = completion.build_completion_item(complete_item("愛", "あい", "愛"), 1, text_edit_range)

  expect.equality(item.label, "愛")
  expect.equality(item.filterText, "あい")
  expect.equality(item.textEdit.newText, "愛")
  expect.equality(item.data.kana, "あい")
  expect.equality(item.data.word, "愛")
  expect.equality(item.data.henkan_type, "okurinasi")
  expect.equality(item.documentation, nil)
end

T["build_completion_item"]["creates item with documentation"] = function()
  local item = completion.build_completion_item(
    complete_item("藍", "あい", "藍;indigo", "okurinasi", "indigo"),
    1,
    text_edit_range
  )

  expect.equality(item.label, "藍")
  expect.no_equality(item.documentation, nil)
  expect.equality(item.documentation.kind, "plaintext")
  expect.equality(item.documentation.value, "indigo")
end

T["build_completion_item"]["prefers the given filter text over the midashi"] = function()
  local item = completion.build_completion_item(complete_item("愛", "あい", "愛"), 1, text_edit_range, "▽あい")

  expect.equality(item.filterText, "▽あい")
end

T["build_completion_item"]["inserts the okurigana with an okuriari candidate"] = function()
  -- 「あたり」を「あた」+「り」に分けて引いた候補。辞書の見出しと候補は送り仮名
  -- を含まないが、挿入する文字列と学習させる見出しは別物になる
  local item =
    completion.build_completion_item(complete_item("当たり", "あたr", "当た", "okuriari"), 1, text_edit_range)

  expect.equality(item.label, "当たり")
  expect.equality(item.textEdit.newText, "当たり")
  expect.equality(item.data.kana, "あたr")
  expect.equality(item.data.word, "当た")
  expect.equality(item.data.henkan_type, "okuriari")
end

T["build_completion_item"]["carries the completion rank into data"] = function()
  local ranked = completion.build_completion_item(
    complete_item("登録", "とうろく", "登録", nil, nil, 4089),
    1,
    text_edit_range
  )
  local unranked = completion.build_completion_item(complete_item("塘路", "とうろ", "塘路"), 2, text_edit_range)

  expect.equality(ranked.data.rank, 4089)
  expect.equality(unranked.data.rank, nil)
end

-- build_completion_items tests
T["build_completion_items"] = new_set()

T["build_completion_items"]["builds items from complete items"] = function()
  local items = completion.build_completion_items({
    complete_item("愛", "あい", "愛"),
    complete_item("藍", "あい", "藍;indigo", "okurinasi", "indigo"),
  }, text_edit_range)

  expect.equality(#items, 2)
  expect.equality(items[1].label, "愛")
  expect.equality(items[2].label, "藍")
end

T["build_completion_items"]["keeps skkeleton's order through sortText"] = function()
  -- skkeleton側でランクの適用と並べ替えが済んでいるので、渡された順がそのまま
  -- 表示順になる必要がある
  local items = completion.build_completion_items({
    complete_item("哀", "あい", "哀"),
    complete_item("愛", "あい", "愛"),
    complete_item("当たり", "あたr", "当た", "okuriari"),
  }, text_edit_range)

  expect.equality(#items, 3)
  expect.equality(items[1].label, "哀")
  expect.equality(items[2].label, "愛")
  expect.equality(items[3].label, "当たり")
  expect.equality(items[1].sortText < items[2].sortText, true)
  expect.equality(items[2].sortText < items[3].sortText, true)
end

T["build_completion_items"]["handles empty items"] = function()
  local items = completion.build_completion_items({}, text_edit_range)

  expect.equality(#items, 0)
end

return T
