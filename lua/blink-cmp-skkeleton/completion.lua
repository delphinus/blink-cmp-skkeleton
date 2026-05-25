--- Completion item builder for blink-cmp-skkeleton
--- @module blink-cmp-skkeleton.completion

local utils = require("blink-cmp-skkeleton.utils")

local M = {}

--- Convert ranks array to map
--- @param ranks_array any[]
--- @return table<string, number>
function M.convert_ranks_to_map(ranks_array)
  local ranks = {}
  for _, rank_entry in ipairs(ranks_array) do
    if rank_entry[1] and rank_entry[2] then
      ranks[rank_entry[1]] = rank_entry[2]
    end
  end
  return ranks
end

--- Build a single completion item
--- @param kana string
--- @param word string
--- @param rank number
--- @param text_edit_range table
--- @param filter_text string|nil Filter text for blink.cmp matching
--- @return blink.cmp.CompletionItem
function M.build_completion_item(kana, word, rank, text_edit_range, filter_text)
  local label, info = utils.parse_word(word)

  local item = {
    label = label,
    kind = vim.lsp.protocol.CompletionItemKind.Text,
    -- filterText: use provided filter_text or fall back to kana
    filterText = filter_text or kana,
    -- Use textEdit to replace the entire pre-edit text (including ▽)
    textEdit = {
      newText = label,
      range = text_edit_range,
    },
    -- sortText for ranking
    sortText = string.format("%010d", 1000000000 - rank),
    data = {
      skkeleton = true,
      kana = kana,
      word = word,
      rank = rank,
    },
  }

  if info ~= "" then
    item.documentation = {
      kind = "plaintext",
      value = info,
    }
  end

  return item
end

--- Build completion items from candidates
--- @param candidates any[]
--- @param ranks table<string, number>
--- @param text_edit_range table
--- @param filter_text string|nil Filter text for blink.cmp matching
--- @return blink.cmp.CompletionItem[]
function M.build_completion_items(candidates, ranks, text_edit_range, filter_text)
  -- Sort candidates by kana (reading)
  table.sort(candidates, function(a, b)
    return a[1] < b[1]
  end)

  -- グローバル辞書由来の候補はユーザー辞書の末尾より配置する
  -- 辞書順に並べるため先頭から順に負の方向にランクを振っていく
  local globalRank = -1
  local items = {}

  for _, cand in ipairs(candidates) do
    local kana = cand[1]

    for _, word in ipairs(cand[2]) do
      local rank = ranks[word] or globalRank
      if not ranks[word] then
        globalRank = globalRank - 1
      end

      local item = M.build_completion_item(kana, word, rank, text_edit_range, filter_text)
      -- アノテーション専用エントリ (word が ";comment" のような形式) は
      -- parse_word 後に label が "" になる。空 label を blink.cmp に渡すと
      -- frizbee の SIMD matcher が空 haystack で panic する
      -- (saghen/frizbee#64, saghen/frizbee#77 参照)。挿入する文字列も無いので
      -- 候補として元々無意味であり、ここで弾く。
      if item.label ~= "" then
        table.insert(items, item)
      end
    end
  end

  -- Sort by rank (same as ddc implementation)
  table.sort(items, function(a, b)
    return a.data.rank > b.data.rank
  end)

  return items
end

return M
