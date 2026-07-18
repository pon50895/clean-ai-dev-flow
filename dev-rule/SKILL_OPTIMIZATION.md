# Skill 優化 (Skill Optimization with SkillOpt)

> 本框架的 skill 層(`scripts/skill.sh`、`.claude/skills/`、dev-rule 中的可複用 SKILL.md)是「給凍結 LLM 的自然語言技能」。與其手動憑感覺改 skill 文字,可用 **SkillOpt** 以資料驅動的方式系統性地優化它們。

## 什麼是 SkillOpt

`https://github.com/microsoft/SkillOpt`(Microsoft,MIT,arXiv:2605.23904)

> text-space optimizer:像訓練神經網路一樣訓練可複用的自然語言 skill —— 有 epoch、(mini-)batch size、learning rate、validation gate —— 但**不碰模型權重**。透過 trajectory-driven edits + validation-gated updates,產出可部署的 `best_skill.md`。

核心想法:把「skill 是一段 prompt/指令文字」當成可優化參數。跑 agent 收集 trajectory(成功/失敗軌跡)→ 依結果對 skill 文字做編輯 → 用 validation set 把關「改了有沒有更好」→ 只接受通過驗證的更新 → 收斂成 `best_skill.md`。

## 為什麼適合本框架

本框架靠「寫得好的 skill / dev-rule 文字」驅動凍結的 Claude/Gemini/Codex。痛點:
- skill 文字是人手寫、憑直覺迭代,沒有客觀「改了有沒有更好」的把關。
- 同一條規則在多次 session 反覆被違反(drift)→ 代表 skill 文字還不夠好。

SkillOpt 提供一條工程化路徑:用真實 agent trajectory 自動演化 skill 文字,validation-gated 確保不退步,適合用來打磨:
- `.claude/skills/` 下的可複用 skill(dispatch / review / handoff 等)。
- dev-rule 中反覆被違反的規則(把 violation trajectory 當訓練訊號)。

## 怎麼接(建議流程)

1. **挑目標 skill**:選一個常被誤用 / 效果不穩的 skill 文字當優化對象。
2. **準備 trajectory**:收集該 skill 的真實使用軌跡(成功 + 失敗案例);本框架已有 violation 持久化(跨 session 學習)可當訓練訊號來源。
3. **定 validation gate**:用一組可重跑的任務當驗證集,確保「新 skill 文字」客觀優於舊版才接受。
4. **跑 SkillOpt**:依其 README(`pip install -e .`、設 `.env` API 憑證)對該 skill 迭代,產出 `best_skill.md`。
5. **回寫 + review**:把 `best_skill.md` 收斂結果回寫到對應 skill / dev-rule,**走 PR 標 `[DEV-RULE]`**(skill 文字也是 SSOT 的一部分,不可繞過人工 review)。

## 邊界

- SkillOpt 優化的是「skill 文字」,不是模型;產物仍是自然語言,需人工 review 後才併入框架(同 dev-rule 修改紀律)。
- 不要把未驗證的自動編輯直接上線;validation gate + PR review 兩道關都要過。

---

*參考整合。實際安裝/跑法以 SkillOpt 官方 repo 為準。修改走 PR 標 `[DEV-RULE]`。*
