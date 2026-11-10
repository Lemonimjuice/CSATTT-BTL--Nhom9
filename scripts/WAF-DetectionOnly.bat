@echo off
rem Bấm đúp file này: WAF chỉ GHI LOG, không chặn (Demo 3: giả lập WAF bị lách luật).
rem Xong Demo 3 phải bấm đúp WAF-On.bat để chặn lại.
call "%~dp0waf-mode.bat" DetectionOnly
echo.
pause
