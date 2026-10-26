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

Lab Compose độc lập trong backend, không ghép root Compose: primary datasource là `sqli-lab-auth-db/lab_identity`, account `lab_identity_app`, không dùng `database`/`postgres` nghiệp vụ. JDBC vulnerable trỏ `sqli-lab-db/sqli_lab`, reader SELECT-only. Hai DB tmpfs, network internal riêng, API chỉ loopback. Credentials/JWT do host runner sinh riêng; login ở lab để lấy token lab. Không tái dùng JWT nghiệp vụ và không lấy credentials từ standalone.

MDC chỉ nhận X-Request-ID dài 1–64 ký tự thuộc `[A-Za-z0-9][A-Za-z0-9._-]*`; input khác được thay UUID. Không đưa Authorization/body vào MDC. JWT filter không log parser exception message vì có thể chứa token/claims. Đây không phải chứng nhận mọi log của toàn hệ thống đã được rà soát; TV2 còn phải che secret trong WAF audit.

## Bằng chứng

Xem bảng phiên hiện tại trong hợp đồng V2. Snapshot lịch sử standalone ngày 26/10/2026 từng báo 27 Maven tests và 26 HTTP cases PASS, SQL init và Hibernate validate PASS. Không tái sử dụng số liệu đó để đánh dấu source hiện tại đạt. Không có bằng chứng WAF hay Nginx failover cho backend thật.

Các script SQL init/Hibernate hiện có được giữ nguyên; Hibernate repo nhóm đã khớp bản fixed standalone ngoại trừ đường dẫn SQL cần khác. Script diagnostic untracked của người dùng được giữ nguyên.
