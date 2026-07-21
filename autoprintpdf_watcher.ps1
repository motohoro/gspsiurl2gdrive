# ==========================================
# 設定項目（必要に応じて変更してください）
# ==========================================
# 1. 監視対象フォルダ（別の場所にする場合は "D:\フォルダ名" のように直接フルパスを指定）
$watchFolder = Join-Path $PSScriptRoot "watch"

# 2. 印刷済みファイルの移動先フォルダ
$printedFolder = Join-Path $PSScriptRoot "printed"

# 3. 印刷済みファイルの保持期間（日数）
$keepDays = 100

# 4. SumatraPDF.exe のパス
$sumatraPath = Join-Path $PSScriptRoot "SumatraPDF.exe"


# --- フォルダがなければ自動作成 ---
if (-not (Test-Path $watchFolder)) { New-Item -Path $watchFolder -ItemType Directory | Out-Null }
if (-not (Test-Path $printedFolder)) { New-Item -Path $printedFolder -ItemType Directory | Out-Null }


# ==========================================
# 0. 起動時：古い印刷済みファイルの自動クリーンアップ
# ==========================================
Write-Host "メンテナンス: 印刷済みフォルダ内の古いファイル（$keepDays 日以前）をチェック中..." -ForegroundColor Cyan

# 削除対象となる基準日時を計算
$expirationDate = (Get-Date).AddDays(-$keepDays)

# 基準日時より古いPDFを取得して削除
$oldFiles = Get-ChildItem -Path $printedFolder -Filter "*.pdf" -File | Where-Object { $_.LastWriteTime -lt $expirationDate }

if ($oldFiles.Count -gt 0) {
    Write-Host "$($oldFiles.Count) 件の古いファイルが見つかりました。削除を開始します..." -ForegroundColor Yellow
    foreach ($file in $oldFiles) {
        try {
            Remove-Item -Path $file.FullName -Force -ErrorAction Stop
            Write-Host "[削除完了] $($file.Name) (最終更新日: $($file.LastWriteTime.ToString('yyyy/MM/dd')))" -ForegroundColor DarkGray
        }
        catch {
            Write-Warning "[削除失敗] $($file.Name): $_"
        }
    }
}
else {
    Write-Host "削除対象の古いファイルはありませんでした。" -ForegroundColor Green
}


# ==========================================
# 印刷 ＆ フォルダ移動の共通処理
# ==========================================
function Process-PdfFile ($filePath) {
    $fileName = Split-Path $filePath -Leaf
    Write-Host "[処理開始] 対象ファイル: $fileName" -ForegroundColor Yellow

    # --- 1. 書き込み完了待ちループ（受信側の書き込み待ち） ---
    $isFileReady = $false
    $retryCount = 0
    $maxRetry = 60 # 最大60秒待機

    while (-not $isFileReady -and $retryCount -lt $maxRetry) {
        try {
            $fileStream = [System.IO.File]::Open($filePath, 'Open', 'Read', 'None')
            $fileStream.Close()
            $isFileReady = $true
        }
        catch {
            $retryCount++
            Start-Sleep -Seconds 1
        }
    }

    # --- 2. 印刷処理 ＆ ロック解除待ち移動 ---
    if ($isFileReady) {
        try {
            # SumatraPDFを使って印刷（画面非表示・自動縮小フィット）
            if (Test-Path $sumatraPath) {
                Start-Process -FilePath $sumatraPath -ArgumentList "-print-to-default -print-settings `"shrink`" `"$filePath`"" -WindowStyle Hidden
            }
            else {
                Start-Process -FilePath $filePath -Verb Print -WindowStyle Hidden
            }
            
            # --- ★ 原因1の対策：印刷完了後のファイルロック解除待ちループ ---
            $isUnlocked = $false
            $unlockRetry = 0
            $maxUnlockRetry = 30 # 最大30秒待機

            while (-not $isUnlocked -and $unlockRetry -lt $maxUnlockRetry) {
                try {
                    # 排他モード（ReadWrite）でファイルが開けるかテスト
                    $testStream = [System.IO.File]::Open($filePath, 'Open', 'ReadWrite', 'None')
                    $testStream.Close()
                    $isUnlocked = $true
                }
                catch {
                    # まだSumatraPDF等のプロセスが掴んでいる場合は1秒待機
                    $unlockRetry++
                    Start-Sleep -Seconds 1
                }
            }

            if (-not $isUnlocked) {
                Write-Warning "[警告] ロック解除待機がタイムアウトしましたが移動を試みます: $fileName"
            }

            # 移動先のフルパスを設定
            $targetPath = Join-Path $printedFolder $fileName

            # 同名ファイルが存在する場合、ファイル名に日時を付与
            if (Test-Path $targetPath) {
                $baseName = [System.IO.Path]::GetFileNameWithoutExtension($fileName)
                $extension = [System.IO.Path]::GetExtension($fileName)
                $timestamp = (Get-Date).ToString("yyyyMMdd_HHmmss")
                $newFileName = "${baseName}_${timestamp}${extension}"
                $targetPath = Join-Path $printedFolder $newFileName
            }

            # ファイル移動の実行
            Move-Item -Path $filePath -Destination $targetPath -Force -ErrorAction Stop
            Write-Host "[完了] 印刷および移動が完了しました: $fileName -> $(Split-Path $targetPath -Leaf)" -ForegroundColor Green
        }
        catch {
            Write-Warning "[エラー] 印刷または移動中にエラーが発生しました: $_"
        }
    }
    else {
        Write-Warning "[タイムアウト] ファイルの書き込み完了を確認できなかったため処理をスキップしました。"
    }
}


# ==========================================
# ① 起動時の一括印刷機能
# ==========================================
Write-Host "起動処理: 監視フォルダ内の既存PDFをチェックしています..." -ForegroundColor Cyan

$existingPdfs = Get-ChildItem -Path $watchFolder -Filter "*.pdf" -File

if ($existingPdfs.Count -gt 0) {
    Write-Host "未処理のPDFが $($existingPdfs.Count) 件見つかりました。順次印刷します..." -ForegroundColor Yellow
    foreach ($pdf in $existingPdfs) {
        Process-PdfFile $pdf.FullName
    }
    Write-Host "既存PDFの一括処理が完了しました。" -ForegroundColor Green
}
else {
    Write-Host "未処理のPDFはありませんでした。" -ForegroundColor Green
}


# ==========================================
# ② リアルタイム常駐監視の設定
# ==========================================
$watcher = New-Object System.IO.FileSystemWatcher
$watcher.Path = $watchFolder
$watcher.Filter = "*.pdf"
$watcher.IncludeSubdirectories = $false
$watcher.EnableRaisingEvents = $true

$action = {
    Process-PdfFile $Event.SourceEventArgs.FullPath
}

Unregister-Event -SourceIdentifier "PdfPrinter" -ErrorAction SilentlyContinue
Register-ObjectEvent $watcher "Created" -SourceIdentifier "PdfPrinter" -Action $action | Out-Null

Write-Host "常駐監視を開始しました。フォルダ: $watchFolder" -ForegroundColor Cyan

# バックグラウンド維持用の無限ループ
while ($true) {
    Start-Sleep -Seconds 5
}