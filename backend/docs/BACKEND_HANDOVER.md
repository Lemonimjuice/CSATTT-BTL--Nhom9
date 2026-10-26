# Backend handover — V2

Tài liệu hiện hành cho repository nhóm: [TV3 V2 handover](../../docs/contract/tv3-v2-handover.md) và [backend README](../README.md). Các hướng dẫn Compose standalone cũ đã được thay thế.

## Hành vi API

- Auth register/login dùng BCrypt và JWT; refresh/logout; từ chối account disabled.
- `POST /api/v1/secure/records` nhận `content`, lấy owner từ principal.
- `GET /api/v1/secure/records/{id}`: owner 200, user khác 403, ID thiếu 404, thiếu/sai JWT 401.
- `POST /api/v1/secure/records/search` nhận JSON `keyword`, bind cả keyword và username. Tìm literal không phân biệt hoa/thường; tối đa 50 dòng own-record; keyword bắt buộc, không blank, tối đa 200 ký tự. `%`, `_`, dấu nháy được coi là dữ liệu.
- `POST /api/v1/vuln/records/search` chỉ tồn tại khi cùng bật profile `sqli-lab` và `SQLI_DEMO_ENABLED=true`; JWT hợp lệ trên main nhận 404. Lab reader chỉ có fixture giả. Startup/runtime checks từ chối cấu hình quyền sai; query lỗi 400, lab unavailable 503; không trả SQL/JDBC exception.
- `GET /actuator/health` public, UP khi sẵn sàng. Không thay thế kiểm tra proxy upstream/failover.

## Cấu hình hiện hành

Main: `integration`, least-privilege DB role, `validate`, show SQL false; hai node chia sẻ JWT/DB/image. Default cũng validate. `dev` chỉ phục hồi workflow update/show SQL local. Không có application-prod.yml; prod trong Logback chỉ chọn cấu hình logger.

Lab Compose độc lập trong backend, không ghép root Compose: primary datasource là `sqli-lab-auth-db/lab_identity`, account `lab_identity_app`, không dùng `database`/`postgres` nghiệp vụ. JDBC vulnerable trỏ `sqli-lab-db/sqli_lab`, reader SELECT-only. Hai DB tmpfs, network internal riêng. Test override bỏ port publish của API; chỉ gateway HTTP tạm publish loopback ngẫu nhiên, API và DB không vào edge. Credentials/JWT do host runner sinh riêng; login ở lab để lấy token lab. Không tái dùng JWT nghiệp vụ và không lấy credentials từ standalone. Gateway test không phải WAF; chi tiết ở [SQLI_TEST_GATEWAY.md](SQLI_TEST_GATEWAY.md).

MDC chỉ nhận X-Request-ID dài 1–64 ký tự thuộc `[A-Za-z0-9][A-Za-z0-9._-]*`; input khác được thay UUID. Không đưa Authorization/body vào MDC. JWT filter không log parser exception message vì có thể chứa token/claims. Đây không phải chứng nhận mọi log của toàn hệ thống đã được rà soát; TV2 còn phải che secret trong WAF audit.

## Bằng chứng

Docker E2E cuối ngày 27/10/2026 đã chạy source nhóm với exit code 0: Maven **39 PASS / 0 failures / 0 errors / 0 skipped**; HTTP secure/lab **30/30 PASS**; two-node HTTP **12/12 PASS** và cả hai startup health UP. Shared JWT, Record hai chiều, IDOR 403, Node2 health/read sau stop Node1, PostgreSQL lab, isolation, loopback gateway và cleanup đều PASS. Hai SQL init và Hibernate validate cũng đã chạy trên DB mới khi khởi động hai node.

Nginx LB/failover qua proxy nhóm và ModSecurity/CRS vẫn **NOT RUN**. Bài direct-node survival và plain HTTP gateway không phải chứng cứ WAF. Log thô và diagnostic chỉ giữ local trong thư mục được Git ignore, không thuộc bản commit bàn giao.

Các script SQL init/Hibernate hiện có được giữ nguyên; Hibernate repo nhóm đã khớp bản fixed standalone ngoại trừ đường dẫn SQL cần khác. Script diagnostic untracked của người dùng được giữ nguyên.
