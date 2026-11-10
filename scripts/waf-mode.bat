@echo off
chcp 65001 >nul
rem Bản Windows của scripts/waf-mode.sh, để đổi chế độ WAF mà không cần Git Bash.
rem Hai file bấm đúp WAF-On.bat và WAF-DetectionOnly.bat gọi file này. Gọi từ CMD/PowerShell cũng được:
rem   scripts\waf-mode.bat                 xem chế độ đang chạy
rem   scripts\waf-mode.bat DetectionOnly   chỉ ghi log, không chặn (Demo 3: giả lập WAF bị lách luật)
rem   scripts\waf-mode.bat On              chặn (mặc định, Demo 2)
rem Chỉ khởi động lại container nginx-waf (vài giây); backend và database không bị ảnh hưởng.
setlocal
cd /d "%~dp0.."
set "LOG=%TEMP%\nhom9-waf-mode.log"

if "%~1"=="" goto show
if "%~1"=="On" goto switch
if "%~1"=="DetectionOnly" goto switch
echo Giá trị không hợp lệ: %~1 (chỉ nhận On hoặc DetectionOnly, phân biệt hoa thường)
exit /b 2

:switch
set "WAF_MODE=%~1"
echo Đang đổi WAF sang chế độ %WAF_MODE%, chờ khoảng 10 giây...
docker compose up -d --no-deps --force-recreate --wait nginx-waf >"%LOG%" 2>&1
if errorlevel 1 goto failed
call :current
echo WAF đang ở chế độ: %MODE%
if not "%MODE%"=="%WAF_MODE%" goto mismatch
if "%MODE%"=="DetectionOnly" echo CẢNH BÁO: WAF chỉ ghi log, KHÔNG chặn. Xong Demo 3 nhớ bấm đúp WAF-On.bat
exit /b 0

:failed
echo LỖI: không khởi động lại được nginx-waf. Kiểm tra Docker Desktop đang chạy và hệ thống đã được dựng.
echo Thông báo của Docker:
type "%LOG%"
exit /b 1

:mismatch
echo LỖI: chưa đổi được sang %WAF_MODE%
exit /b 1

:show
docker compose exec -T nginx-waf true >nul 2>&1
if errorlevel 1 goto notrunning
call :current
echo WAF đang ở chế độ: %MODE%
exit /b 0

:notrunning
echo Không xem được: container nginx-waf chưa chạy. Mở Docker Desktop và bật hệ thống trước.
exit /b 1

:current
set "MODE=On"
docker compose exec -T nginx-waf grep -q "SecRuleEngine DetectionOnly" /etc/nginx/modsecurity-mode.conf >nul 2>&1
if not errorlevel 1 set "MODE=DetectionOnly"
exit /b 0
