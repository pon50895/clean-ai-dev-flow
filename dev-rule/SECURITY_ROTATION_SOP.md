# 密鑰輪換標準作業程序 (Secrets Rotation SOP)

> **本文件對應 SECURITY_WORKTREES.md 第 D 條 (`chore/rotate-secrets`)。**
> D-1 (本 PR) 只建立 baseline 安全網；D-2 / D-3 是後續維運窗口工作。

---

## 1. 已知洩漏清單 (Known-leaked Secrets)

下列 fallback 預設值寫死在 `docker-compose.yml`，且已 push 到 GitHub origin。
**git 歷史不會自動清除**，必須在各服務輪換新值，並把舊值視為**永久洩漏**。

| 服務 | 變數 | 洩漏值（部分遮蔽） | 嚴重性 | 影響範圍 |
|------|------|---------------------|--------|----------|
| PostgreSQL | `POSTGRES_PASSWORD` | `q0iTtGG…rbM` | HIGH | local + 任何用此 fallback 的環境 |
| JWT 簽章 | `JWT_SECRET` | `bWo9VMfy…F3jw==` | **CRITICAL** | 可偽造任何使用者 token |
| Redis | `REDIS_PASSWORD` | `p4tgNFVt…NMs` | HIGH | session / Socket.io adapter |
| 金流供應商 | `<PAYMENT_HASH_KEY>`, `<PAYMENT_HASH_IV>` | （不得放在 `.env.example` 真值）| MED | 金流簽章驗證 |

> **說明**：JWT_SECRET 洩漏的等級之所以列 CRITICAL，是因為任何擁有此值的人可
> 偽造 admin token 通過伺服器端 auth middleware 的驗證。

---

## 2. 三階段輪換計畫

### D-1：Baseline 安全網（本 PR 已完成）
- `.gitignore` 加 `.env.*` 全擋 + 白名單 `.env.example` / `.env.*.example`
- `.gitignore` 加 `secrets/`、`*.pem`、`credentials.json` 等
- `.env.example` 把真值改為 `__REPLACE_WITH_*__`
- `.githooks/pre-commit` 加 secret-scan（純 grep，無外部依賴）
  - 偵測：OpenAI / AWS / GitHub / Slack / Google API key / 私鑰 PEM / JWT
  - 繞過：`ALLOW_SECRET_COMMIT=1 git commit ...`

**結果**：未來 commit 不會再洩漏，但**過去已洩漏的 secret 仍有效**。

---

### D-2：移除 fallback + 輪換 local 密鑰（**已於本 PR 完成 2026-05-05；pre-launch 不需公告**）

**Pre-launch 例外**：本專案尚未上線，沒有現存使用者 token 也沒有需要保護的客戶資料，
所以原本「發 dev 公告 + 維運窗口」的前置條件被移除。一旦上線後，未來任何
`docker-compose.yml` 變動仍須照 D-3 流程走。

#### D-2.1 移除 `docker-compose.yml` 的 fallback 與 hardcoded 寫法（DONE）
| 位置 | 改前 | 改後 |
|------|------|------|
| `services.postgres.environment` | `POSTGRES_PASSWORD: ${POSTGRES_PASSWORD:-q0iTtGG...}` | `${POSTGRES_PASSWORD:?POSTGRES_PASSWORD required (run scripts/init-local-env.sh)}` |
| `services.server.environment.DATABASE_URL` | 內嵌 `:q0iTtGG...@postgres:` | 內嵌 `:${POSTGRES_PASSWORD:?...}@postgres:` |
| `services.server.environment.JWT_SECRET` | `${JWT_SECRET:-bWo9VMfy...}` | `${JWT_SECRET:?JWT_SECRET required (HS256, base64 of >=32 random bytes)}` |
| `services.server.environment.REDIS_PASSWORD` | `${REDIS_PASSWORD:-p4tgNFVt...}` | `${REDIS_PASSWORD:?REDIS_PASSWORD required}` |
| `services.redis.command` | `redis-server --requirepass p4tgNFVt...` | shell-form `sh -c 'exec redis-server --requirepass "$$REDIS_PASSWORD"'` + `environment.REDIS_PASSWORD` |
| `services.redis.healthcheck` | `redis-cli -a p4tgNFVt... ping` | `CMD-SHELL` 讀 `$REDIS_PASSWORD` env，`--no-auth-warning` 抑制噪音 |

驗證指令（在乾淨 shell 中跑）：
```bash
# 應 fail-fast
env -i HOME=/tmp PATH=/usr/local/bin:/usr/bin:/bin docker compose config
# -> "required variable POSTGRES_PASSWORD is missing a value: POSTGRES_PASSWORD required (run scripts/init-local-env.sh)"

# 用 init script 產 .env 後應 pass
bash scripts/init-local-env.sh
env -i HOME=/tmp PATH=/usr/local/bin:/usr/bin:/bin docker compose --env-file .env config
# -> 沒有任何 q0iTtGG / bWo9VMfy / p4tgNFVt literal
```

#### D-2.2 開發者 local 輪換 — 改用 `scripts/init-local-env.sh`
```bash
# 一次性 bootstrap（不覆寫既有 .env 的真實值）
bash scripts/init-local-env.sh

# 想看會做什麼但不寫入：
bash scripts/init-local-env.sh --dry-run

# 強制輪 JWT_SECRET（會失效所有現存 token；上線後再做要走 D-3.2）：
bash scripts/init-local-env.sh --force-jwt

# 完成後重起 stack（DESTRUCTIVE：local DB 會清掉，pre-launch OK）：
docker compose down -v && docker compose up -d
```

腳本特性：
- 32-byte base64 給 PG/Redis、48-byte base64 給 JWT
- 檔案模式強制 `chmod 600`
- 密碼**不**輸出到 stdout 或 history
- 既有 `.env` 中已是真值的欄位**絕不覆寫**（除非 `--force-jwt`）
- 用 Python 替換避免 sed/awk 對 `+` `/` `=` 的轉義地雷

#### D-2.3 Git 歷史處理（**仍建議不做**）
雖然 `docker-compose.yml` 改完後舊 fallback 值再也不能啟動 stack，但 GitHub
公開歷史仍可見舊值。Pre-launch 也照此原則處理：
| 選項 | 做法 | 副作用 |
|------|------|--------|
| (a) 不做（**推薦**）| 視為永久洩漏，依賴 D-2.1 的新密鑰 + D-3 的生產輪換 | GitHub 公開歷史仍可見，但已無實際攻擊面（pre-launch 無使用者資料）|
| (b) `git filter-repo` 重寫 | `pip install git-filter-repo && git filter-repo --replace-text patterns.txt` | 所有 fork / clone / PR 失效，commit hash 全變；風險 > 效益 |

---

### D-3：生產上線前最後一哩（Production Cutover）

**禁止在白天非維運窗口執行。** 任何步驟失敗會中斷使用者。

#### D-3.1 第三方平台密鑰重發清單

| 平台 | 動作 | 影響 | 同步發版？ |
|------|------|------|-----------|
| Google Cloud Console | 重發 OAuth Client Secret | OAuth 流程暫斷 | 是 |
| LINE Developers | 重發 Channel Secret | LINE Login 暫斷 | 是 |
| 金流供應商後台 | 重申請 HashKey/IV | 金流 callback 簽章驗證失敗（含進行中訂單） | **嚴重，需先公告**|
| OpenAI Platform | Revoke 舊 API key + 發新 | AI 推論暫斷 | 是 |
| Cloudflare R2 | 重發 Access Key | 圖檔上傳/讀取暫斷 | 是 |
| AWS IAM | 重發 Access Key | S3 / SES 暫斷 | 是 |
| 即時通訊 / 視訊供應商 | Revoke ServerSecret | 連線暫斷 | 是 |
| Gmail SMTP | 重發 App Password | 郵件發送暫斷 | 是 |
| Sentry | 重發 DSN | 錯誤上報靜默失敗（不擋功能） | 否 |
| GitHub Actions Secrets | 一鍵更新（Settings → Secrets）| CI 暫紅 | 否 |

#### D-3.2 生產 JWT_SECRET 輪換（最痛點）
- **副作用**：所有現存使用者 token 立即失效，全部被踢回登入頁
- **緩解**：
  1. 提前 24 小時公告（站內公告 + email + LINE 群組）
  2. 選離峰時段（凌晨 3-5 點）
  3. 改前端 401 處理：自動跳轉登入並保留 `returnTo`
  4. 監控登入流量，準備擴容

#### D-3.3 順序（建議）
```
1. 維運窗口前 24h：發公告
2. 窗口開始：put up maintenance page
3. 重發所有 D-3.1 secrets，更新 GitHub Actions Secrets
4. 部署用新 secrets 的版本
5. 驗證：登入、OAuth、金流測試交易、檔案上傳
6. 撤下 maintenance page
7. 監控 1 小時，確認登入率回正常
```

---

## 3. 日常規範

### 3.1 新增 secret
1. 加進 `.env`（**絕不**進 `.env.example`）
2. 在 `.env.example` 加同名變數，值用 `__REPLACE_WITH_<NAME>__`
3. 在本檔 §1 表格登錄

### 3.2 偵測到歷史洩漏
1. **第一時間到該服務 revoke 舊值並發新**（不是先想著重寫 git 歷史）
2. 更新 GitHub Actions Secrets / 部署環境
3. 在本檔 §1 加一行記錄
4. 寫 post-mortem 進 `.planning/incidents/`

### 3.3 pre-commit hook 觸發誤報
```bash
# 確認真的是 placeholder / 已 revoked 的 fixture
ALLOW_SECRET_COMMIT=1 git commit -m "..."
```
**不要把 hook patterns 拿掉**，要的話補白名單路徑（在 `.githooks/pre-commit` §2 的 `:(exclude)` 列表）。

---

## 4. 檢核清單模板（給未來執行 D-2/D-3 的人）

### D-2 執行前
- [ ] 在 `#dev` 頻道發公告 ≥ 24h
- [ ] 提供 `.env.dev` 範本給開發者
- [ ] 確認 CI 用的 secrets 也同步準備

### D-2 執行
- [ ] `docker-compose.yml` 改 `${VAR:?missing}` 形式
- [ ] redis `command:` 改 env 注入
- [ ] 自己的 local stack 砍重建驗證
- [ ] commit + PR

### D-3 執行前
- [ ] 站內公告 ≥ 24h
- [ ] email + LINE 推播
- [ ] 確認所有第三方平台後台帳密在手
- [ ] 準備 maintenance page
- [ ] 準備 rollback 計畫（保留舊 secrets 一份在 1Password / Vault 至少 7 天）

### D-3 執行
- [ ] put up maintenance page
- [ ] 依 §D-3.1 表格逐項輪換
- [ ] 更新 GitHub Actions Secrets
- [ ] 部署
- [ ] 驗證登入 / OAuth / 金流 / 上傳
- [ ] 撤下 maintenance
- [ ] 1h 監控

---

*D-1 完成日期：2026-05-05*
*D-2 完成日期：2026-05-05（pre-launch 跳過公告窗口）*
*D-3 執行人：待指派（生產上線前 24h 啟動）*
