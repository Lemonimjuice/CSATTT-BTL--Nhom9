# Minh chứng kiểm thử

Thư mục này chỉ giữ vài ảnh quan trọng cho báo cáo; bản gốc lưu trên Drive của nhóm.
Trước khi chụp hoặc chép log: che `Authorization`, access/refresh token và mật khẩu.

## Cách thu thập

1. Chạy hệ thống và toàn bộ demo, lưu kết quả ra file:

   ```bash
   sh tests/demo/run-all.sh > logs/demo-run.txt 2>&1
   ```

   Output không chứa token hay mật khẩu.

2. Log của hệ thống đã được gom sẵn vào thư mục `logs/` trên máy khi chạy:
   - `logs/nginx/access.log` — log truy cập Nginx (có `rid`, `upstream`)
   - `logs/waf/modsec_audit.log` — audit log ModSecurity (JSON; không chứa header/body nên không lộ JWT, mật khẩu)
   - `logs/backend-node-1/audit.log`, `logs/backend-node-2/audit.log` — log ứng dụng (có `reqId`, `user`, `ip`)

   Xem nhanh một giao dịch WAF theo request ID:

   ```bash
   sh scripts/waf-audit.sh <X-Request-ID>
   ```

3. Với từng ảnh chụp Burp, ghi kèm `X-Request-ID` của response. Mã này trùng `unique_id` trong
   `modsec_audit.log`, `rid=` trong log Nginx và `reqId=` trong log backend, giúp người chấm đối chiếu 3 lớp.

## Danh sách ảnh đề xuất

| Demo | Ảnh |
|---|---|
| 1 | `X-Upstream` luân phiên 2 node; sau `docker compose stop backend-node-1` mọi request vẫn `200` với token cũ; log Nginx có `upstream=<node1>, <node2>` |
| 2 | Burp: SQLi vào `/api/v1/vuln/records/search` nhận `403` + `X-Blocked-By: waf`; dòng `modsec_audit.log` có `ruleId 100100` cùng `unique_id` |
| 3 | Cùng payload khi `WAF_MODE=DetectionOnly`: bản lỗi trả 3 dòng `LAB-ONLY`, bản vá trả `[]`; UNION sang `public.users` nhận `400`; audit log có `is_interrupted: false` |
| 4 | Burp: User B `PUT /api/v1/secure/posts/3` nhận `403` không có `X-Blocked-By`; log backend dòng `user=user_b ... -> 403 ... ip=<IP client>`; `/api/v1/vuln/posts/3` trả email `user_a@nhom9.test` |
| Bổ sung | Intruder brute-force: vài `401` rồi `429`; `curl -H 'X-Forwarded-For: 6.6.6.6'` nhưng log backend vẫn ghi IP thật |
