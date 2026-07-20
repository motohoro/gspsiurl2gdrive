@echo off
setlocal enabledelayedexpansion
chcp 932 > nul

set "CURRENT_DIR=%~dp0"
if "%CURRENT_DIR:~-1%"=="\\" set "CURRENT_DIR=%CURRENT_DIR:~0,-1%"

echo ==================================================
echo  PDF自動印刷監視タスク 自動登録ツール
echo ==================================================
echo.
echo [1] 登録処理を開始します...
echo 実行フォルダ: %CURRENT_DIR%
echo.

set "TEMP_XML=%CURRENT_DIR%\temp_task.xml"
set "PS_PATH=%CURRENT_DIR%\autoprintpdf_watcher.ps1"

:: 一時XMLの書き出し (UTF-16LE)
powershell -NoProfile -ExecutionPolicy Bypass -Command "$xml = '<?xml version=\"1.0\" encoding=\"UTF-16\"?><Task version=\"1.2\" xmlns=\"http://schemas.microsoft.com/windows/2004/02/mit/task\"><RegistrationInfo><Description>PDFフォルダ自動印刷監視</Description></RegistrationInfo><Triggers><LogonTrigger><Enabled>true</Enabled></LogonTrigger></Triggers><Principals><Principal id=\"Author\"><RunLevel>HighestAvailable</RunLevel></Principal></Principals><Settings><MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy><DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries><StopIfGoingOnBatteries>false</StopIfGoingOnBatteries><AllowHardTerminate>true</AllowHardTerminate><StartWhenAvailable>false</StartWhenAvailable><RunOnlyIfNetworkAvailable>false</RunOnlyIfNetworkAvailable><IdleSettings><StopOnIdleEnd>true</StopOnIdleEnd><RestartOnIdle>false</RestartOnIdle></IdleSettings><AllowStartOnDemand>true</AllowStartOnDemand><Enabled>true</Enabled><Hidden>false</Hidden><RunOnlyIfIdle>false</RunOnlyIfIdle><WakeToRun>false</WakeToRun><ExecutionTimeLimit>PT0S</ExecutionTimeLimit><Priority>7</Priority></Settings><Actions Context=\"Author\"><Exec><Command>powershell.exe</Command><Arguments>-WindowStyle Hidden -ExecutionPolicy Bypass -File \"\"%PS_PATH%\"\"</Arguments></Exec></Actions></Task>'; [System.IO.File]::WriteAllText('%TEMP_XML%', $xml, [System.Text.Encoding]::Unicode)"

:: タスク登録
schtasks /create /tn "PDF自動印刷監視" /xml "%TEMP_XML%" /f > nul 2>&1

if %errorlevel% equ 0 (
    echo [成功] タスク「PDF自動印刷監視」を登録しました！
    echo        ※PCの起動（ログオン）時に裏で自動的に動き始めます。
    echo.
    echo 今すぐ監視を開始する場合は、タスクスケジューラから実行するか、
    echo PCを再起動（ログオン）してください。
) else (
    echo [失敗] タスク登録に失敗しました。
    echo        管理者権限が必要です。「install.bat」を右クリックして
    echo        「管理者として実行」を選択してください。
)

if exist "%TEMP_XML%" del "%TEMP_XML%"

echo.
echo ==================================================
pause
