@echo off
chcp 65001 >nul
rem Máy nạn nhân: tra một request trong cả 3 lớp theo mã X-Request-ID (máy tấn công đọc từ response).
rem Bấm đúp rồi dán mã, hoặc gọi: scripts\Tra-RequestID.bat <mã>
setlocal
set "RID=%~1"
if "%RID%"=="" set /p "RID=Dán X-Request-ID (32 ký tự) rồi Enter: "
if "%RID%"=="" goto end
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0xem-log.ps1" -Rid "%RID%"
:end
echo.
pause
