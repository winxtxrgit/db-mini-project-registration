@echo off
rem Windows: double-click to open the Plan A web app at http://127.0.0.1:5050
rem Details are in scripts\run_web.py (keep this file ASCII-only so cmd.exe reads it correctly)
setlocal
cd /d "%~dp0"

rem Python output is Thai text: switch the console to UTF-8
chcp 65001 >nul
set PYTHONUTF8=1

rem Prefer the "py" launcher, fall back to "python"
set "PY="
where py >nul 2>nul && set "PY=py -3"
if not defined PY (
  where python >nul 2>nul && set "PY=python"
)
if not defined PY goto nopython
%PY% -c "import sys; sys.exit(0 if sys.version_info >= (3, 9) else 1)" >nul 2>nul
if errorlevel 1 goto nopython

%PY% scripts\run_web.py %*
set "RC=%errorlevel%"
if not "%RC%"=="0" (
  echo.
  echo Could not start the web app ^(exit %RC%^). See the message above.
  pause
)
exit /b %RC%

:nopython
echo Python 3.9 or newer is required: https://www.python.org/downloads/
echo During install, tick "Add python.exe to PATH".
pause
exit /b 1
