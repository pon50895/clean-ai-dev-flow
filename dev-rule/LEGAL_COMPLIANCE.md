# 法律合規與同意協議標準 (Legal & Compliance)

## 1. Click-wrap 強制閱讀機制
- **前端實作**:
    - 容器高度固定為 `h-32` (128px) 或 `h-24`。
    - 溢出屬性必須為 `overflow-y-auto`。
    - 必須綁定 `onScroll` 事件，當 `scrollTop + clientHeight >= scrollHeight - 5` 時標記為已讀。
    - 在未讀取到底部前，`Checkbox` 與 `Submit Button` 必須保持 `disabled` 狀態。
- **多語系支援**:
    - 內容必須讀取自 `packages/shared-content/legal.json`。
    - 頁面必須根據 `i18n.language` 動態切換 `zh` 或 `en` 內容。

## 2. 後端審計標準
- **欄位要求**: `User`, `AdminUser`, `TeacherApplication` 必須具備 `acceptedLegalAt` (DateTime?)。
- **校驗邏輯**: 所有註冊 API 入口點必須強制檢查 `acceptedLegal: true`。

## 3. 共享內容結構
```json
{
  "zh": { "terms": { "title": "...", "sections": [...] } },
  "en": { "terms": { "title": "...", "sections": [...] } }
}
```
