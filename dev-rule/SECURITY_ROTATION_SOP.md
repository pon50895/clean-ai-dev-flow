# 密鑰輪換標準作業程序 (Secrets Rotation SOP)

> 通用密鑰輪換流程。專案專屬的密鑰清單（哪些 vendor、哪些 env var）請寫進專案 `.planning/SECRETS_INVENTORY.md`，本檔只規範流程。

---

## 1. 已知洩漏清單 (Known-leaked Secrets) — 專案層維護

每個專案應在 `.planning/SECRETS_INVENTORY.md` 維護以下表格，列出**已洩漏**或**疑似已洩漏**的密鑰：

| 服務 | 變數 | 洩漏值（部分遮蔽） | 嚴重性 | 影響範圍 | 輪換狀態 |
|------|------|---------------------|--------|----------|----------|
| `<service-name>` | `<ENV_VAR_NAME>` | `<masked-value>` | LOW / MED / HIGH / CRITICAL | <受影響系統> | pending / rotated / monitored |

**嚴重性指引**：
- **CRITICAL**：可偽造身份 / 解密歷史資料 / 完整 admin 權限（例：JWT_SECRET、root DB password、cloud account access key）
- **HIGH**：服務層 API key、payment vendor secret、PII 加密 key
- **MED**：第三方整合 API key（ChatOps、analytics、notification service）
- **LOW**：監控 / observability key（Sentry DSN、log shipper token）

---

## 2. 三階段輪換計畫

### D-1：Baseline 安全網（每個專案 launch 前必做）

- `.gitignore` 加 `.env*` 全擋 + 白名單 `.env.example` / `.env.*.example`
- `.gitignore` 加 `secrets/`、`*.pem`、`*.key`、`credentials.json` 等
- `.env.example` 所有真值改為 `__REPLACE_WITH_*__` placeholder
- `.husky/pre-commit` 加 secret-scan（純 grep，無外部依賴）
  - 偵測：OpenAI / AWS / GitHub / Slack / Google API key / 私鑰 PEM / JWT
  - 繞過：`ALLOW_SECRET_COMMIT=1 git commit ...`

**結果**：未來 commit 不會再洩漏，但**過去已洩漏的 secret 仍有效**，須走 D-2 / D-3 處理。

---

### D-2：移除 fallback + 輪換 local 密鑰（pre-launch / dev 環境）

#### D-2.1 移除 `docker-compose.yml` 的 fallback 與 hardcoded 寫法

| 改前 | 改後 |
|------|------|
| `${VAR:-leaked-default}` | `${VAR:?VAR required (run scripts/init-local-env.sh)}` |
| 內嵌 `:hardcoded@host:` 連線字串 | 內嵌 `:${VAR:?...}@host:` |
| `command: redis-server --requirepass leaked-pass` | shell-form `sh -c 'exec redis-server --requirepass "$$VAR"'` + `environment.VAR` |
| `healthcheck: redis-cli -a leaked-pass ping` | `CMD-SHELL` 讀 `$VAR` env，`--no-auth-warning` 抑制噪音 |

驗證指令（在乾淨 shell 中跑）：

```bash
# 應 fail-fast（環境變數沒帶就掛）
env -i HOME=/tmp PATH=/usr/local/bin:/usr/bin:/bin docker compose config

# 用 init script 產 .env 後應 pass
bash scripts/init-local-env.sh
env -i HOME=/tmp PATH=/usr/local/bin:/usr/bin:/bin docker compose --env-file .env config
# -> 沒有任何 leaked literal
```

#### D-2.2 開發者 local 輪換 — 採用 `scripts/init-local-env.sh`

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

腳本應有的特性：
- 32-byte base64 給 PG/Redis、48-byte base64 給 JWT
- 檔案模式強制 `chmod 600`
- 密碼**不**輸出到 stdout 或 history
- 既有 `.env` 中已是真值的欄位**絕不覆寫**（除非明確 `--force-*` flag）
- 用 Python 替換避免 sed/awk 對 `+` `/` `=` 的轉義地雷

#### D-2.3 Git 歷史處理（**通常不建議重寫歷史**）

雖然 `docker-compose.yml` 改完後舊 fallback 值再也不能啟動 stack，但 GitHub 公開歷史仍可見舊值。

| 選項 | 做法 | 副作用 |
|------|------|--------|
| (a) 不做（**推薦**）| 視為永久洩漏，依賴 D-2.1 的新密鑰 + D-3 的生產輪換 | GitHub 公開歷史仍可見，但已無實際攻擊面 |
| (b) `git filter-repo` 重寫 | `pip install git-filter-repo && git filter-repo --replace-text patterns.txt` | 所有 fork / clone / PR 失效，commit hash 全變；風險 > 效益 |

---

### D-3：生產上線前最後一哩（Production Cutover）

**禁止在白天非維運窗口執行。** 任何步驟失敗會中斷使用者。

#### D-3.1 第三方平台密鑰重發清單（專案層客製）

每個專案在 `.planning/SECRETS_INVENTORY.md` 維護表格：

| 平台 | 動作 | 影響 | 需公告？ |
|------|------|------|---------|
| `<vendor-name>` | `<rotation-action>` | `<service-impact>` | yes / no |

常見 vendor 類型（依專案自行填入）：
- OAuth provider（Google / Microsoft / Apple / LINE）
- Payment vendor（Stripe / 在地金流商）
- AI / 推論 API（OpenAI / Anthropic / Google AI）
- Object storage（S3 / R2 / GCS）
- Cloud IAM Access Key（AWS / GCP / Azure）
- Email / SMS provider
- Video / chat / RTC（Twilio / Agora 或自架 SFU）
- Monitoring（Sentry / DataDog）
- CI secrets（GitHub Actions / GitLab CI）

#### D-3.2 生產 JWT_SECRET 輪換（最痛點）

- **副作用**：所有現存使用者 token 立即失效，全部被踢回登入頁
- **緩解**：
  1. 提前 24 小時公告（站內公告 + email + IM 群組）
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
3. 在 `.planning/SECRETS_INVENTORY.md` 表格登錄

### 3.2 偵測到歷史洩漏

1. **第一時間到該服務 revoke 舊值並發新**（不是先想著重寫 git 歷史）
2. 更新 GitHub Actions Secrets / 部署環境
3. 在 `.planning/SECRETS_INVENTORY.md` 加一行記錄
4. 寫 post-mortem 進 `.planning/incidents/`

### 3.3 pre-commit hook 觸發誤報

```bash
# 確認真的是 placeholder / 已 revoked 的 fixture
ALLOW_SECRET_COMMIT=1 git commit -m "..."
```

**不要把 hook patterns 拿掉**，要的話補白名單路徑（在 `.husky/pre-commit` 的 `:(exclude)` 列表）。

---

## 4. 檢核清單模板（給未來執行 D-2/D-3 的人）

### D-2 執行前
- [ ] 在 IM 頻道發公告 ≥ 24h（如果有其他 dev 在用 local stack）
- [ ] 提供 `.env.dev` 範本給開發者
- [ ] 確認 CI 用的 secrets 也同步準備

### D-2 執行
- [ ] `docker-compose.yml` 改 `${VAR:?missing}` 形式
- [ ] redis `command:` 改 env 注入
- [ ] 自己的 local stack 砍重建驗證
- [ ] commit + PR

### D-3 執行前
- [ ] 站內公告 ≥ 24h
- [ ] email + IM 推播
- [ ] 確認所有第三方平台後台帳密在手
- [ ] 準備 maintenance page
- [ ] 準備 rollback 計畫（保留舊 secrets 一份在密碼管理器至少 7 天）

### D-3 執行
- [ ] put up maintenance page
- [ ] 依 `.planning/SECRETS_INVENTORY.md` D-3.1 表格逐項輪換
- [ ] 更新 GitHub Actions Secrets
- [ ] 部署
- [ ] 驗證登入 / OAuth / 金流 / 上傳
- [ ] 撤下 maintenance
- [ ] 1h 監控

---

## 5. 與其他文件的關係

| 文件 | 關係 |
|------|------|
| `dev-rule/SECURITY_STANDARDS.md` §11.4 | 機敏資料外洩偵測（偵測到洩漏後本檔規範如何輪換）|
| `.planning/SECRETS_INVENTORY.md` | 專案層密鑰清單（已洩漏列表 + D-3.1 vendor 清單）|
| `scripts/init-local-env.sh` | 本檔 D-2.2 的執行層腳本（每個專案自行撰寫）|
| `.husky/pre-commit` | 本檔 D-1 / §3.3 的 secret-scan 攔截器 |

---

*本檔為通用流程 SOP；專案專屬內容（vendor 清單、密鑰名稱、輪換範本）請寫在 `.planning/SECRETS_INVENTORY.md`。*
