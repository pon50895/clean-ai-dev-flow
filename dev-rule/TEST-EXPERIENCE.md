# 測試實戰經驗與「坑」總結 (TEST-EXPERIENCE)

通用部分，取自多個專案累積的 E2E / 整合測試經驗。專案專屬的坑請另開章節累積在本檔末尾（章節 9 起）。

## 1. 資料庫 Seed 與測試帳號同步 (Crucial)
- **問題**：重跑 seed 會重置資料庫，導致測試專用帳號消失或密碼被覆蓋。
- **經驗**：
  - Seed 必須明確包含測試所需的帳號與 mock 資料。
  - 測試腳本與 seed 腳本的帳密必須逐字同步（常見：結尾驚嘆號漏掉）。
  - 對測試帳號用 `update` / upsert 邏輯強制更新，不要因為「帳號已存在」就跳過。

## 2. Upsert 與唯一性約束
- **問題**：對非唯一欄位做 `upsert` 會報錯，提示需要 id 或複合唯一鍵。
- **經驗**：先審 schema 確認哪些欄位真的唯一；非唯一時改用 `findFirst` 判斷再決定 `create` 或 `update`。

## 3. 大型資產不進 Git
- **問題**：把幾十 MB 的原始圖檔推進 Git 會讓倉庫肥大，且歷史清不掉。
- **經驗**：圖 / 大檔放物件儲存（S3 / R2 等），repo 只存 URL；本地 fixture 路徑加進 `.gitignore`；檔名標準化成與資料 ID 對應的格式，簡化 seed。

## 4. E2E 與環境變數
- **問題**：測試腳本裡寫死 `BASE_URL`，換 port 或換 docker 後全部失效。
- **經驗**：URL 統一收斂在 E2E 框架設定檔（例：`playwright.config.ts`），測試內只用相對路徑（`page.goto('/login')`）。

## 5. 容器內的指令執行
- **問題**：在宿主機用 `docker exec` 跑指令，常因工作目錄不對而找不到檔案。
- **經驗**：先切目錄再執行：`docker exec <c> sh -c "cd <app-dir> && <cmd>"`。

## 6. 前端依賴相容性
- **問題**：主框架升大版本後，白屏或 `Cannot read properties of undefined` 類錯誤，來自依附套件仍是舊版（canvas、動畫、表單庫最常見）。
- **經驗**：框架大版本升級時，依附其內部 API 的套件必須同步升；遇到框架內部欄位 `undefined` 的錯誤，先查版本是否對齊，再查程式碼。

## 7. DB schema 與 ORM client 不同步（API 500）
- **問題**：API 500，log 顯示 `column ... does not exist`。
- **原因**：schema 檔已更新但資料庫欄位尚未建立，或 ORM client 還是舊的。
- **經驗**：依序做三件事：同步 schema 到 DB → 重新 generate client → 重跑 seed。只有特定 API 壞掉時，先看 server log 的 ORM 報錯。

## 8. ORM client 單例
- **問題**：不同層級的檔案各自 `new Client()` 或用易錯的相對路徑引用，造成連線池耗盡與交易不一致。
- **經驗**：整個專案只保留一個 client 實例出口，其他檔案一律從該處 import；禁止在 service 或測試腳本內自行建立實例。
