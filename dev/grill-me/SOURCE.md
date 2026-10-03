# 出處 / Provenance — grill-me

- **改造自(fork)**:mattpocock/skills
- **原始 skill**:`grill-me`(+ 折入 `grilling` 的訪談機制)
- **原始路徑**:`skills/productivity/grill-me/SKILL.md`、`skills/productivity/grilling/SKILL.md`
- **原始 raw URL**:
  - https://raw.githubusercontent.com/mattpocock/skills/main/skills/productivity/grill-me/SKILL.md
  - https://raw.githubusercontent.com/mattpocock/skills/main/skills/productivity/grilling/SKILL.md
- **License**:MIT

## 原版做什麼(摘要)

`grill-me` 是薄殼,只呼叫 `/grilling`。`grilling` 的核心:一次一題地逼問 plan / decision / idea 的每個分支,每題附推薦答案;能查的事實自己查,決策才問人;達成共識前不動手。

## 我改了什麼

- 全文繁中重寫,並把 `grilling` 機制折進來,使 skill 自足(不依賴未安裝的 `grilling`)。
- 接上本專案 GSD 四階段的 **Discuss** 關卡;定位成 R2(禁腦補需求)的防線。
- 「該問什麼」全換命理平台脈絡:範圍 / 驗收條件 / 既有 spec 衝突 / worktree 佔用(`.planning/HANDOFF/`)/ 定位法遵 / 風險假設。
- 收尾產「共識摘要」交給 Plan 階段寫 `.planning/phases/<phase>/PLAN.md`;牽涉領域模型時改用 `grill-with-docs`。
