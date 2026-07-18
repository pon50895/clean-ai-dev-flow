# 資訊安全規範 (Security Standards)

本規範整合 **OWASP Top 10 (2021)**、反滲透 (Anti-Penetration) 與個資保護要求。所有 AI 助手與開發人員提交代碼前，**必須**逐項檢查本文件。專案專屬的業務語境（具體服務名、Port 配置、第三方廠商）請寫進根目錄 `CLAUDE.md` 的「業務紅線」段。

---

## 0. 總則 (General Principles)

| 原則 | 內涵 |
|------|------|
| **最小權限 (Least Privilege)** | 任何角色 / 服務帳號 / Token 僅授予完成任務的最小權限。 |
| **零信任 (Zero Trust)** | 內網服務（DB / cache / WebSocket / 微服務）視同公開網路，皆需驗證。 |
| **深度防禦 (Defense in Depth)** | 同一風險至少有兩層防線（例：WAF + 應用層驗證 + DB 約束）。 |
| **預設安全 (Secure by Default)** | 所有功能初始為「拒絕」，必須明確授權才放行。 |
| **可稽核 (Auditable)** | 所有寫入 / 權限變更 / 登入事件必須留下不可竄改的日誌。 |

---

## 1. OWASP A01:2021 — 失效的存取控制 (Broken Access Control)

### 強制規範
- **R1.1** 所有 `/api/*` 路由（除登入、註冊、健康檢查）**必須**經過 `authenticate` middleware。
- **R1.2** 多租戶資源查詢**必須**強制過濾 `orgId`，禁止僅依賴 `x-org-id` header；服務層需呼叫 `requireOrgMembership()`。
- **R1.3** 角色檢查使用集中式 `requireRole(['SUPER_ADMIN', 'ORG_ADMIN'])`，禁止在 controller 內手寫 `if (user.role === 'X')`。
- **R1.4** 物件級別授權 (IDOR)：每筆資源讀寫前，必須驗證 `resource.orgId === req.orgId` 或 `resource.userId === req.userId`。
- **R1.5** Super Admin 跨租戶切換**必須**寫入 `securityLogger.roleChange()` 審計日誌。

### 禁忌
- 禁止在前端依賴 UI 隱藏作為授權手段。
- 禁止在 URL 直接傳遞 `orgId` 而不進行 server-side 驗證。

---

## 2. OWASP A02:2021 — 加密失效 (Cryptographic Failures)

### 強制規範
- **R2.1 密碼**：使用 `bcrypt` cost ≥ 12 或 `argon2id`；禁止 MD5/SHA1/SHA256。
- **R2.2 JWT 簽署**：
  - **必須**明確指定 `algorithm: 'HS256'`（或 RS256），禁止 `algorithm: 'none'`。
  - `JWT_SECRET` 長度 ≥ 64 bytes，由 `crypto.randomBytes(64)` 產生，**禁止任何後備預設值** (`|| 'your-secret-key'`)。
  - `expiresIn` ≤ 7 天；refresh token 另行管理並可吊銷。
- **R2.3 Token 儲存**：
  - 瀏覽器端 Access Token **必須** 使用 `httpOnly + Secure + SameSite=Strict` Cookie，**禁止** `localStorage` / `sessionStorage`。
- **R2.4 隨機性**：所有 token / OTP / reset code **必須**使用 `crypto.randomBytes()`，禁止 `Math.random()`；長度 ≥ 32 hex chars。
- **R2.5 傳輸層**：所有外部流量 **必須** 強制 HTTPS (TLS 1.2+)；Nginx 設定 `Strict-Transport-Security: max-age=31536000; includeSubDomains; preload`。
- **R2.6 OAuth state**：必須 HMAC 簽署，禁止僅 base64 編碼。
- **R2.7 PII 欄位**：身份證、信用卡末四碼、手機等存入 JSON 欄位前須使用 `pgcrypto` 或應用層加密。

---

## 3. OWASP A03:2021 — 注入 (Injection)

### 強制規範
- **R3.1 輸入驗證**：所有 API 端點 **必須** 透過 `zod` schema 驗證 `req.body`/`req.query`/`req.params`。Schema 失敗回 400，**禁止** 直接讀取未驗證欄位。
- **R3.2 SQL**：禁止 `prisma.$queryRaw` / `$executeRaw` 拼接字串；如需原生查詢，**必須** 使用 `Prisma.sql` 範本字串並通過 code review。
- **R3.3 NoSQL / Redis**：key 必須 prefix 隔離 (`org:${orgId}:user:${userId}`)，禁止用戶可控字串作為完整 key。
- **R3.4 命令注入**：禁止 `child_process.exec(userInput)`；如需執行外部程式，使用 `execFile` 並嚴格 allowlist 參數。
- **R3.5 XSS**：
  - React `dangerouslySetInnerHTML` 禁止使用，例外需使用 `DOMPurify.sanitize()` 並在 PR 標註理由。
  - 所有 Markdown / 富文本顯示一律經 `DOMPurify` 過濾。
  - URL 跳轉須白名單檢查，避免 Open Redirect。
- **R3.6 i18n 內容**：翻譯檔禁止包含 HTML tag；如需富排版，請拆為多個 key 在 React 內組裝。

---

## 4. OWASP A04:2021 — 不安全設計 (Insecure Design)

### 強制規範
- **R4.1** 新功能需在 `.planning/` 階段填寫 **威脅模型 (Threat Model)** 段落 (STRIDE)。
- **R4.2** 涉及金流、健康資料、個資的功能須通過資安 review 才能進入 Execute 階段。
- **R4.3** Rate Limit 必須分層：
  - Global: `100 req / min / IP`
  - Auth (login/register/reset): `5 req / 5 min / IP + email`
  - Payment callback: 簽章驗證 + IP 白名單。
- **R4.4** 業務邏輯漏洞防護：取消、退款、轉帳等**必須**使用資料庫交易 (transaction) 並加 Optimistic Lock。

---

## 5. OWASP A05:2021 — 安全設定錯誤 (Security Misconfiguration)

### 強制規範
- **R5.1 Helmet**：所有 Express 服務 **必須** `app.use(helmet())`，CSP 禁用 `unsafe-inline` / `unsafe-eval`。
- **R5.2 CORS**：`origin` 必須白名單，禁止 `*`；`credentials: true` 時不可配 `origin: '*'`。
- **R5.3 容器**：
  - Node 容器 `USER node`（非 root）。
  - 鏡像版本鎖定 SHA256 digest，禁止 `latest`。
  - 健康檢查不可包含明文密碼（改用 `--no-auth-warning` + env 載入）。
- **R5.4 對外端口**：僅 80/443 對 0.0.0.0；DB / cache / 內部微服務僅綁 `127.0.0.1` 或 docker 內網。
- **R5.5 錯誤回應**：生產環境 `NODE_ENV=production` 時，回應禁止包含 stack trace、SQL、檔案路徑。
- **R5.6 預設帳號**：禁止在 production 部署如 `admin@example.com / Admin123!` 等弱密碼種子帳號；種子腳本須讀取 env 或拒絕在 prod 執行。

---

## 6. OWASP A06:2021 — 易損與過期元件 (Vulnerable & Outdated Components)

### 強制規範
- **R6.1** CI **必須** 跑 `npm audit --audit-level=high`，發現 `high/critical` 阻擋合併。
- **R6.2** 每月執行 `npm outdated` 並建立升級 PR；`high/critical` CVE 須於 7 天內修補。
- **R6.3** 禁止使用以下不安全套件版本（持續更新；專案層補充於 `CLAUDE.md`）：
  - `jsPDF < 3.0.1`
  - `protobufjs < 7.2.5`
  - `quill < 2.0.0`
- **R6.4** 第三方 CDN 引用 **必須** 加 SRI (`integrity="sha384-..."`)。

---

## 7. OWASP A07:2021 — 識別與認證失效 (Identification & Authentication Failures)

### 強制規範
- **R7.1 密碼策略**：≥ 10 字元，必含大小寫 + 數字 + 符號；後端用 zxcvbn 評分 ≥ 3。
- **R7.2 帳號鎖定**：同一帳號 5 次登入失敗 → 鎖 15 分鐘；同一 IP 10 次 → 鎖 1 小時。
- **R7.3 MFA**：管理員 (`SUPER_ADMIN`, `ORG_ADMIN`) **必須** 啟用 TOTP 或 WebAuthn。
- **R7.4 Session 失效**：登出、修改密碼、變更權限後，全部既存 token 須失效（採 JWT jti + Redis blacklist 或 token version 欄位）。
- **R7.5 OAuth**：第三方登入 callback 必須驗證 `state`（HMAC 簽章）與 nonce。
- **R7.6 WebSocket**：連線時 **必須** 透過 query token 或 first-message authentication 驗證 JWT；驗證失敗立即 `close(1008)`。房間名須對應使用者可見之資源（不可信任 client 提供）。

---

## 8. OWASP A08:2021 — 軟體與資料完整性失效 (Software & Data Integrity Failures)

### 強制規範
- **R8.1 Webhook 驗證**：第三方（金流、IM、payment provider）callback 必須驗證 HMAC-SHA256 簽章與 timestamp（避免 replay）。
- **R8.2 CI 供應鏈**：`package-lock.json` 必須提交；CI 用 `npm ci` 而非 `npm install`。
- **R8.3 反序列化**：禁止對使用者輸入做 `JSON.parse` 後直接 spread 至 Prisma `data`，必須先過 zod schema。
- **R8.4 上傳檔案**：除 MIME 檢查外，**必須** 用 `file-type` 套件驗 magic bytes；圖片走 `sharp` 重新編碼，剝除 EXIF。
- **R8.5 程式碼簽署**：production deploy artifact 須附 SHA256 並對比。

---

## 9. OWASP A09:2021 — 安全日誌與監控失效 (Security Logging & Monitoring Failures)

### 強制規範
- **R9.1** 必紀錄事件（採 `securityLogger`）：
  - 登入成功 / 失敗、登出
  - 角色變更、權限變更
  - 密碼 / Email 變更
  - 大金額交易、退款
  - API key 使用
  - Super Admin 切租戶
- **R9.2** 日誌**禁止**包含明文密碼、JWT、信用卡完整號、CVV；email/手機需遮罩。
- **R9.3** 日誌保留 ≥ 180 天；高敏感區（金流）≥ 1 年。
- **R9.4** 需設定告警：
  - 5 分鐘內同帳號失敗 ≥ 5 → IM 告警（Slack / Discord / Teams）
  - 1 小時內 5xx 比例 ≥ 5% → 值班通知 (PagerDuty / OpsGenie)
  - Sentry 採樣 production ≤ 0.1，dev = 1.0。
- **R9.5** 日誌寫入後 **不可** 修改 (append-only)；Loki/Elastic 需限制 delete 權限。

---

## 10. OWASP A10:2021 — 伺服端請求偽造 (SSRF)

### 強制規範
- **R10.1** 所有從伺服器發起的 HTTP 請求 (axios/fetch)，URL **必須**：
  - 協議僅允許 `https:`（內部呼叫例外清單列於程式碼註釋）
  - 禁止解析後落入私網 (`10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`, `127.0.0.0/8`, `169.254.0.0/16`)
- **R10.2** 圖片 / URL 預覽功能需走 SSRF-safe proxy（如 `image-proxy` 或 sandbox）。
- **R10.3** 升級 axios ≥ 1.8.2（修補 SSRF CVE）。

---

## 11. 反滲透 (Anti-Penetration) 專章

### 11.1 攻擊面收斂
- Production 環境 **僅** 對外暴露 80/443。其餘服務（內部 API、cache、DB、微服務）須位於 docker 內網或 VPC private subnet。
- Nginx 移除 `Server` header；隱藏版本號。
- 禁用 HTTP `TRACE/TRACK` 方法。

### 11.2 偵測與誘餌
- 部署 fail2ban（基於 nginx access log），對掃描行為自動封鎖 IP。
- 設置 honeypot endpoint：`/.env`、`/wp-admin`、`/phpmyadmin` 命中即封 IP 並告警。

### 11.3 入侵後遏制
- 應用容器以 `read-only` rootfs 啟動 (`read_only: true`)，僅 `/tmp` 與必要 volume 可寫。
- Outbound egress allowlist：應用容器僅可外連白名單域名（例：第三方 API、payment vendor、object storage）。
- DB credentials 使用 IAM / Vault 短期簽發；禁止長效密碼。

### 11.4 機敏資料外洩偵測
- 啟用 git pre-commit `gitleaks` 與 `secretlint`，阻擋 secret 進入版控。
- CI `gitleaks detect` 失敗即 break build。
- 已洩漏密鑰 **24 小時內** 必須輪換並重新發行（流程見 `SECURITY_ROTATION_SOP.md`）。

### 11.5 滲透測試節奏
- **每季 (Quarterly)**：跑 `scripts/security-audit.sh` 全量自動化掃描。
- **每半年**：邀請外部紅隊或執行 OWASP ZAP / Burp Suite 主動掃描。
- **每年**：第三方 PCI-DSS / ISO 27001 風格稽核（視業務敏感度）。

---

## 12. 個資與合規 (PDPA / GDPR)

- **R12.1** 蒐集 PII 前必須顯示同意條款與目的。
- **R12.2** 提供使用者「下載個資」與「刪除帳戶」API（軟刪除 + 30 天硬刪除排程）。
- **R12.3** PII 出境（如使用美國雲服務）須在隱私政策揭露。
- **R12.4** 兒童資料 (< 13 歲) 須監護人同意流程。

---

## 13. 強制檢核點 (Enforcement)

| 階段 | 檢核 | 工具 |
|------|------|------|
| **Pre-commit** | 阻擋 `.env` / 密鑰 / Emoji | husky + gitleaks + 自訂 hook |
| **Pre-push** | `npm audit` / lint / type-check | husky |
| **CI** | `scripts/security-audit.sh`、Snyk、CodeQL | GitHub Actions |
| **PR Review** | 本文件 R1–R10 逐項勾選 | PR template checklist |
| **Pre-deploy** | DAST (OWASP ZAP baseline) | CI pipeline |
| **Runtime** | Sentry / Loki 告警 | 監控平台 |

### PR 安全檢核 Template
```markdown
## Security Checklist (R1–R10)
- [ ] R1 Access Control：所有新增路由經過 authenticate + 多租戶過濾
- [ ] R2 Crypto：未引入 localStorage 儲存 token、未硬編 secret
- [ ] R3 Injection：所有輸入經 zod 驗證、無 dangerouslySetInnerHTML
- [ ] R5 Misconfig：未新增公開埠、未降級 CORS / CSP
- [ ] R6 Components：`npm audit` 無新增 high/critical
- [ ] R7 Auth：未繞過 MFA / Rate limit / 帳號鎖定
- [ ] R8 Integrity：webhook 簽章驗證、上傳走 magic bytes 檢查
- [ ] R9 Logging：敏感操作有 securityLogger 紀錄、無 PII 入 log
- [ ] R10 SSRF：新增 outbound 請求有 URL allowlist
- [ ] Anti-pen：未對外暴露內部服務
```

---

## 14. 自動化測試腳本

請參考 `scripts/security-audit.sh`（若存在），至少於以下時機執行：
1. 每次 PR Merge 前。
2. 每次 production 部署前。
3. 每週排程 (CI cron)。

腳本涵蓋：依賴弱點掃描、Secret 掃描、容器設定檢查、HTTP 安全標頭探測、認證旁路測試、開放埠掃描。

---

## 15. 違規處理

| 嚴重度 | 處理流程 |
|--------|----------|
| **Critical (P0)** | 立即 rollback / 關停服務、24h 內輪換密鑰、72h 內公告 |
| **High (P1)** | 7 天內修復、暫停非必要新功能合併 |
| **Medium (P2)** | 進入下次 sprint 修復 |
| **Low (P3)** | backlog 列管 |

---

*主要參考: OWASP Top 10 (2021), CIS Benchmark, NIST SP 800-53, PDPA / GDPR。專案層業務專屬紅線（具體服務名、Port、第三方 vendor）請寫進根目錄 `CLAUDE.md`。*
