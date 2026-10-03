# dev/ — 工程訪談 skill 收藏(改造自 mattpocock/skills)

動工前的結構化訪談 skill,補 GSD **Discuss** 階段的工具缺口:在寫任何 code / plan 前把需求、決策樹、術語問清楚,防止憑腦補開工(R2)。繁中重寫,並把上游依賴的 `grilling` / `domain-modeling` 機制折進來,使每支自足。出處見各資料夾 `SOURCE.md` 與根目錄 `SOURCES.md`。

| skill | 一句話 | 觸發時機 |
|---|---|---|
| `grill-me` | 一次一題逼問把需求 / 決策釘死 | 進 Plan 前 / 需求模糊 / stress-test 想法 |
| `grill-with-docs` | 逼問 + 同步建領域模型(glossary / ADR) | 設計牽涉領域模型 / 術語 / schema |

兩者關係:純需求釐清用輕量的 `grill-me`;牽涉領域模型 / 術語(八字取用神、運限四化、金流狀態機、Prisma schema)時用 `grill-with-docs`,訪談同時把術語與決策落文件。收尾都交給 Plan 階段寫 `.planning/phases/<phase>/PLAN.md`。
