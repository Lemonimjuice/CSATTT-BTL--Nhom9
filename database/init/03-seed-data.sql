\set ON_ERROR_STOP on
-- Dữ liệu mẫu cho kiểm thử và 4 demo. Chạy sau 01-schema.sql và 02-least-privilege.sql,
-- bằng tài khoản quản trị trong lúc PostgreSQL khởi tạo volume trống.
-- Cùng file này được nạp cho DB chính (blogdb) và DB định danh của lab (lab_identity).
--
-- Tài khoản THỬ NGHIỆM (chỉ dùng trên máy lab, không dùng ở nơi khác):
--   admin   / Admin@Nhom9-2026   (ADMIN)
--   user_a  / UserA@Nhom9-2026   (USER)  - chủ bài nháp dùng cho Demo 4
--   user_b  / UserB@Nhom9-2026   (USER)  - người tấn công IDOR trong Demo 4
-- Mật khẩu lưu dạng băm BCrypt cost 10, không lưu bản rõ trong DB.
BEGIN;

INSERT INTO public.users (username, email, password, role, enabled, created_at, updated_at) VALUES
    ('admin',  'admin@nhom9.test',  '$2a$10$djNiR55F7U1AYn6YBSFpfeIAtUu7.IEAqoE0oNQX6Ug4zSWlyjsy6', 'ADMIN', true, now(), now()),
    ('user_a', 'user_a@nhom9.test', '$2a$10$qpnFgc01ktPj2yb3mmyMJOg8MzY6pR0naYV82gdz0aJQNZy.lbFH2', 'USER',  true, now(), now()),
    ('user_b', 'user_b@nhom9.test', '$2a$10$R.IW3j.ALdoav4KwHIcbvOTXeBoFHbGWbnSmYH6WqLf8Xh7KikSdm', 'USER',  true, now(), now());

INSERT INTO public.categories (name, slug, description, created_at, updated_at) VALUES
    ('Bảo mật web', 'bao-mat-web', 'Bài viết về an toàn ứng dụng web', now(), now()),
    ('Thông báo',   'thong-bao',   'Thông báo chung', now(), now());

-- Mỗi bài một câu INSERT để ID cố định (DB mới): 1 admin, 2 A công khai, 3 A NHÁP, 4 B công khai.
-- Script demo, Postman và mẫu Burp dùng các ID này.
INSERT INTO public.posts (title, slug, content, summary, status, author_id, category_id, created_at, updated_at)
SELECT 'Thông báo khai giảng lab', 'thong-bao-khai-giang-lab', 'Lab Defense in Depth của nhóm 9 đã sẵn sàng.',
       'Thông báo chung', 'PUBLISHED', u.id, c.id, now(), now()
FROM public.users u, public.categories c WHERE u.username = 'admin' AND c.slug = 'thong-bao';

INSERT INTO public.posts (title, slug, content, summary, status, author_id, category_id, created_at, updated_at)
SELECT 'Bài công khai của User A', 'bai-cong-khai-cua-user-a', 'Nội dung công khai, ai cũng đọc được.',
       'Bài đã xuất bản', 'PUBLISHED', u.id, c.id, now(), now()
FROM public.users u, public.categories c WHERE u.username = 'user_a' AND c.slug = 'bao-mat-web';

INSERT INTO public.posts (title, slug, content, summary, status, author_id, category_id, created_at, updated_at)
SELECT 'Bản nháp bí mật của User A', 'ban-nhap-bi-mat-cua-user-a', 'Nội dung nháp chưa công bố, chỉ User A và ADMIN được đọc.',
       'Bản nháp', 'DRAFT', u.id, c.id, now(), now()
FROM public.users u, public.categories c WHERE u.username = 'user_a' AND c.slug = 'bao-mat-web';

INSERT INTO public.posts (title, slug, content, summary, status, author_id, category_id, created_at, updated_at)
SELECT 'Bài công khai của User B', 'bai-cong-khai-cua-user-b', 'User B giới thiệu bản thân.',
       'Bài đã xuất bản', 'PUBLISHED', u.id, NULL, now(), now()
FROM public.users u WHERE u.username = 'user_b';

INSERT INTO public.comments (content, post_id, author_id, parent_id, depth, deleted, created_at, updated_at)
SELECT 'Bài viết hay, cảm ơn User A!', p.id, u.id, NULL, 0, false, now(), now()
FROM public.posts p JOIN public.users u ON u.username = 'user_b'
WHERE p.slug = 'bai-cong-khai-cua-user-a';

-- Record cho Demo 3 (secure search): cả A và B đều có nội dung chứa "alpha",
-- tìm kiếm chỉ được trả về Record của chính người gọi.
-- ID cố định: 1, 2 của A; 3, 4 của B.
INSERT INTO public.secure_records (content, owner_id)
SELECT 'LAB-ONLY alpha report', id FROM public.users WHERE username = 'user_a';
INSERT INTO public.secure_records (content, owner_id)
SELECT 'alpha internal memo của A', id FROM public.users WHERE username = 'user_a';
INSERT INTO public.secure_records (content, owner_id)
SELECT 'alpha note của User B', id FROM public.users WHERE username = 'user_b';
INSERT INTO public.secure_records (content, owner_id)
SELECT 'beta note của User B', id FROM public.users WHERE username = 'user_b';

COMMIT;
