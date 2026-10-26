# Mẫu request cho Burp Suite

Mỗi file `.http` là một request thô: dán vào **Repeater** (chuột phải > Paste) hoặc **Intruder**.
Target: `https://localhost:443`. Thay `<TOKEN_...>` bằng `accessToken` lấy từ request đăng nhập tương ứng.
Không chụp token, mật khẩu vào ảnh báo cáo.

## Cấu hình Burp

1. Proxy > Options: listener `127.0.0.1:8080` (mặc định).
2. Chứng chỉ của lab là tự ký: trong Burp không cần làm gì thêm; nếu dùng trình duyệt qua Burp, cài CA của Burp như bình thường.
3. Rate limit của Nginx: 5 request/giây (API chung) và 5 request/phút, burst 5 (đăng nhập). Với Intruder, đặt
   Resource pool tối đa 1 request đồng thời, delay 300 ms; riêng kịch bản brute-force thì để nhanh để thấy `429`.

## Kịch bản theo demo

| File | Demo | Kỳ vọng |
|---|---|---|
| `01-login-user-a.http`, `02-login-user-b.http` | chuẩn bị | `200`, lấy `accessToken` |
| `03-lab-login-user-a.http`, `04-lab-login-user-b.http` | chuẩn bị (lab) | `200`, token chỉ dùng cho `/api/v1/vuln/...` |
| `10-demo2-sqli-vuln.http` | Demo 2 | WAF On: `403`, header `X-Blocked-By: waf`, audit có rule `100100` |
| `11-demo2-sqli-secure.http` | Demo 2/3 | WAF On: `403` (CRS 942xxx). WAF DetectionOnly: `200 []` |
| `12-demo3-sqli-vuln-detection.http` | Demo 3 | WAF DetectionOnly: `200`, lộ đủ 3 dòng giả của lab |
| `20-demo4-idor-read-secure.http` | Demo 4 | `403` từ backend, KHÔNG có `X-Blocked-By` |
| `21-demo4-idor-update-secure.http` | Demo 4 | `403` từ backend |
| `22-demo4-idor-delete-secure.http` | Demo 4 | `403` từ backend |
| `23-demo4-no-token.http` | Demo 4 | `401` |
| `24-demo4-idor-read-vuln.http` | Demo 4 (đối chứng) | `200`, đọc được nháp, thấy email `user_a@nhom9.test` |
| `25-demo4-idor-update-vuln.http` | Demo 4 (đối chứng) | `200`, sửa được bài của A |
| `30-bruteforce-login.http` | Rate limit | Intruder, payload danh sách mật khẩu: vài `401` đầu, sau đó `429` |
| `31-xss-query.http` | WAF | `403` (CRS 941xxx) |

## Chuyển chế độ WAF (Demo 3)

```bash
WAF_MODE=DetectionOnly docker compose up -d --no-deps --force-recreate nginx-waf
```

Trả lại chế độ chặn:

```bash
WAF_MODE=On docker compose up -d --no-deps --force-recreate nginx-waf
```

## Tra bằng chứng theo request ID

Mỗi response có header `X-Request-ID`. Cùng mã đó là `unique_id` trong audit log WAF và `reqId` trong log backend:

```bash
sh scripts/waf-audit.sh <X-Request-ID>
```

```bash
docker compose logs backend-node-1 backend-node-2 | grep <X-Request-ID>
```
