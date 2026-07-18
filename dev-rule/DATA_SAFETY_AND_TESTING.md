# 資料安全與測試紀律 (Data Safety & Testing Discipline)

> 從一次真實事故萃取:integration test 的無範圍 `deleteMany()` 在共用 dev/QA 資料庫上清空了整批業務資料,且**無備份可還原**。本文件是 AI 與人都必須遵守的硬規則,避免重演。

---

## 1. 紅線:絕不對共用資料庫跑「破壞性測試」

**破壞性測試** = beforeAll/setup 內含**無 WHERE 範圍**的刪除(`deleteMany()`、`TRUNCATE`、`DELETE` 無條件),會清整張表。

- **絕不**讓這類測試對「共用 dev / QA / staging / production」資料庫執行。一跑就清光所有人的資料。
- 這類測試**只能對「專用、可丟棄的 test 資料庫」**跑(每次測試自帶建置 / reset)。
- AI 在「驗證某段 code」時,**先確認該測試的 setup 會不會清庫**,再決定能不能跑。看到無範圍 `deleteMany()` → 預設不可對共用庫跑。

### 1.1 強制防護:test-DB guard
在每個含無範圍刪除的測試 setup **最前面**加一道 fail-fast 守門,DB 名稱不含 `test` 標記就直接 throw:

```ts
export function assertTestDatabase(): void {
  const url = process.env.DATABASE_URL || '';
  const dbName = url.split('/').pop()?.split('?')[0] ?? '';
  if (!/test/i.test(dbName) && process.env.ALLOW_DESTRUCTIVE_TESTS !== '1') {
    throw new Error(
      `拒絕對非 test 資料庫 "${dbName}" 執行破壞性測試 (無範圍 deleteMany)。` +
      `請指向專用 test DB (名稱含 "test") 或設 ALLOW_DESTRUCTIVE_TESTS=1。`
    );
  }
}
```

- 寧可讓測試「fail-fast 跑不了」,也不要「默默清掉共用庫」。
- 正解是 CI / 本機跑這些測試前指向獨立 test DB(如 `<app>_test`)。

### 1.2 範圍化測試(優先)
測試清理優先用**範圍化刪除**(`deleteMany({ where: { orgId: testOrgId } })`),只刪本測試自己造的資料,而非整表。新測試一律這樣寫。

---

## 2. 備份是強制,不是 nice-to-have

- 上述事故之所以「無法還原」,是因為**根本沒有備份**。
- 任何承載真實 / QA 資料的資料庫,**必須有自動備份**(`pg_dump` 定期 / volume 快照 / 託管 DB 的 PITR),且驗證過可還原。
- 「我等等再設備份」= 下次資料事故就是永久損失。**先有備份,再放心做有風險的操作。**

---

## 3. 本機 dev 容器的兩個陷阱

### 3.1 bind-mount 不可靠熱重載
- 把 host 原始碼 bind-mount 進容器跑 dev server(tsx-watch / vite)時,**檔案變更事件在 docker-on-Mac 常不可靠傳入容器** → 改了 code 容器沒重載 → 你以為新 code 生效了其實沒有。
- 驗證行為前先確認「容器跑的是不是最新 code」;不確定就 `docker restart` 該容器。

### 3.2 啟動腳本裡的破壞性 seed / push
- 容器啟動腳本常含 `prisma db push --accept-data-loss`(schema 不符會 DROP 欄位/表)+ `db seed`(seed 內也可能有**無範圍 deleteMany**,例如重建 reference 資料)。
- 所以「restart 容器」不是無害動作:可能跑 schema push + 清/重建 seed 資料。restart 前先確認這兩步對現有資料安全(schema 相符 = push no-op;seed 是否會清掉你在意的表)。

---

## 4. Migration 安全

- Schema 變更優先**只增不減**(additive:加欄位 nullable / 加 default / 加表),prod 升級才安全。
- 刪欄位 / 改型別 / 加 unique 這類**破壞性 migration**,先確認資料相容 + 有備份 + 走 review。
- `db push --accept-data-loss` 是 dev 快速迭代的 footgun:切到「schema 不同」的 branch 重啟會 DROP 該 branch 沒有的表。dev 也建議走 `migrate deploy`(所有 schema 變更先 commit 成 migration)。

---

## 5. 測試分層(快速參考)

| 層 | 工具 | 範圍 |
|----|------|------|
| 單元 | 純函式測試 (vitest/jest) | 無 DB、無 I/O |
| 元件 / 回歸 | component test (Playwright CT 等) | 渲染 + 互動,mock 邊界 |
| 整合 / E2E | 完整 E2E(需 seed fixtures + **專用 test DB**) | 跨服務真實流程 |

- **push 前先測**(unit → 受影響 E2E → 冒煙),不要「先 push 再補測」把驗證責任丟給人。
- **不要對使用者正在 live QA 的環境 / 共用 session 跑 E2E**(會污染 redis session、留 orphan、製造假 bug)。用獨立環境或請使用者自己看。

---

*此文件源自真實事故的事後檢討。修改走 PR 標 `[DEV-RULE]`。*
