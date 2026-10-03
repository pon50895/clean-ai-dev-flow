# SOURCES — 改造採用的外部 skill 出處

本收藏(`marketing/`、`dev/`)裡的 skill 是**改造自**下列開源 repo 的精選子集,非原封照抄:全部繁中重寫,對齊「問問命理平台」定位(命盤=系統規格書非判決書、賦權非恐嚇、去宿命論、B2C 先行、pre-revenue 口碑期)與法遵紅線(供應商一律「AI」、不宣稱未發生的驗證 / 審核、不寫死價錢、台灣式去 AI 腔),並砍掉與此階段無關的段。每個 skill 資料夾內另有 `SOURCE.md` 記錄逐支細節。

## 上游 repo(均 MIT License)

| 上游 repo | License | 用途 |
|---|---|---|
| [coreyhaines31/marketingskills](https://github.com/coreyhaines31/marketingskills) | MIT | 行銷 skill(`marketing/`) |
| [mattpocock/skills](https://github.com/mattpocock/skills) | MIT | 工程訪談 skill(`dev/`) |

MIT 需保留 attribution;本表 + 各 `SOURCE.md` 即為 attribution 記錄。本收藏本身隨 repo 採 BSD 3-Clause(見 `LICENSE`),不影響上游 MIT 條款。

## 對照表:我方 skill → 上游 path → 改動摘要

| 我方 skill | 上游 repo | 上游 path | 改動摘要 |
|---|---|---|---|
| `marketing/product-marketing` | coreyhaines31/marketingskills | `skills/product-marketing/SKILL.md` | 定位 SSOT 落 `docs/strategy/PRODUCT_MARKETING_CONTEXT.md`+綁 NARRATIVE_PLAYBOOK;十二節全換命理定位 |
| `marketing/free-tools-growth` | coreyhaines31/marketingskills | `skills/free-tools/SKILL.md` | 改成榨乾現有免費工具漏斗;砍付費廣告 / 大規模段 |
| `marketing/social-media` | coreyhaines31/marketingskills | `skills/social/SKILL.md` | 平台改 FB/IG/Threads;hook 去恐嚇去宿命論;砍 A-B / 大規模投放 |
| `marketing/referral-programs` | coreyhaines31/marketingskills | `skills/referrals/SKILL.md` | 對齊已建 ?ref;非金錢誘因;砍 affiliate 大軍 / 佣金結構 |
| `dev/grill-me` | mattpocock/skills | `skills/productivity/grill-me/SKILL.md`(+`grilling`) | 折入 grilling 機制自足;接 GSD Discuss;防腦補(R2) |
| `dev/grill-with-docs` | mattpocock/skills | `skills/engineering/grill-with-docs/SKILL.md`(+`grilling`+`domain-modeling`) | 折入兩機制自足;接 GSD Discuss + 領域術語 SSOT |

## 原文追溯

各 `SOURCE.md` 附上游 raw URL,可直接追回原文。原文亦可於上游 repo 對應 path 查閱。
