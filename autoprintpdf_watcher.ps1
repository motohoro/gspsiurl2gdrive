# ==========================================
# 設定項目（必要に応じて書き換えてください）
# ==========================================
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path

# 1. 監視対象フォルダ（別の場所にする場合は "D:\フォルダ名" のように書き換え）
$watchFolder = Join-Path $scriptPath "watch"

# 2. 印刷済みファイルの移動先フォルダ
$printedFolder = Join-Path $scriptPath "printed"

# 3. SumatraPDF.exe のパス
$sumatraPath = Join-Path $scriptPath "SumatraPDF.exe"


# --- フォルダがなければ自動作成 ---
if (-not (Test-Path $watchFolder)) { New-Item -Path $watchFolder -ItemType Directory | Out-Null }
if (-not (Test-Path $printedFolder)) { New-Item -Path $printedFolder -ItemType Directory | Out-Null }


# ==========================================
# 印刷 ＆ フォルダ移動の共通処理
# ==========================================
function Process-PdfFile ($filePath) {
    $fileName = Split-Path $filePath -Leaf
    Write-Host "[処理開始] 対象ファイル: $fileName" -ForegroundColor Yellow

    # --- 1. 書き込み完了待ちループ ---
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

    # --- 2. 印刷 & 移動 ---
    if ($isFileReady) {
        try {
            # SumatraPDFを使って印刷（画面非表示・自動縮小フィット）
            if (Test-Path $sumatraPath) {
                Start-Process -FilePath $sumatraPath -ArgumentList "-print-to-default -print-settings `"shrink`" `"$filePath`"" -WindowStyle Hidden
            }
            else {
                Start-Process -FilePath $filePath -Verb Print -WindowStyle Hidden
            }
            
            # プリンタへのスプール（データ送信）を少し待つための安全マージン
            Start-Sleep -Seconds 3

            # 移動先のフルパスを設定
            $targetPath = Join-Path $printedFolder $fileName

            # 同名ファイルが移動先に存在する場合、ファイル名に日時を付与して衝突を避ける
            if (Test-Path $targetPath) {
                $baseName = [System.IO.Path]::GetFileNameWithoutExtension($fileName)
                $extension = [System.IO.Path]::GetExtension($fileName)
                $timestamp = (Get-Date).ToString("yyyyMMdd_HHmmss")
                $newFileName = "${baseName}_${timestamp}${extension}"
                $targetPath = Join-Path $printedFolder $newFileName
            }

            # ファイルを移動
            Move-Item -Path $filePath -Destination $targetPath -Force
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

# フォルダ内にある既存のPDFをすべて取得
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

# 新規作成イベント発生時のアクション
$action = {
    # 共通処理関数を呼び出す
    Process-PdfFile $Event.SourceEventArgs.FullPath
}

# イベントの登録解除と再登録
Unregister-Event -SourceIdentifier "PdfPrinter" -ErrorAction SilentlyContinue
Register-ObjectEvent $watcher "Created" -SourceIdentifier "PdfPrinter" -Action $action | Out-Null

Write-Host "常駐監視を開始しました。フォルダ: $watchFolder" -ForegroundColor Cyan

# バックグラウンド維持用の無限ループ
while ($true) {
    Start-Sleep -Seconds 5
}
