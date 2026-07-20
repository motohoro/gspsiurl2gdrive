// ==========================================
// 【設定エリア】お使いの環境に合わせて変更してください
// ==========================================
const DRIVE_FOLDER_ID = 'ここにGoogle Driveの保存先フォルダIDを貼り付けます'; 
const TEMPLATE_SLIDE_ID = 'ここに事前準備で控えたテンプレートスライドのIDを貼り付けます; 

// PDFの上部に載せたいスプレッドシートの「列番号」を複数指定（A列=1, B列=2...）
// 例：A列（名前）、B列（受付日時）のデータを載せたい場合
// const TEXT_COLUMNS = [1, 2]; 
const TEXT_COLUMNS = [1, 2]; 

// 画像URLが書き込まれる「列番号」をすべて前から順に指定
const IMAGE_URL_COLUMNS = [4, 5]; 

// 完成したPDFのリンクを書き込む列番号（空いている列を指定。例：H列=8）
const STATUS_COLUMN = 6; 
// ==========================================

function createPdfFromRow(e) {
  if (e.changeType === 'INSERT_ROW' || e.changeType === 'EDIT') {
    
    // 外部サービスからの書き込み遅延を考慮し、2秒待機
    Utilities.sleep(2000);
    
    const sheet = SpreadsheetApp.getActiveSpreadsheet().getActiveSheet();
    const lastRow = sheet.getLastRow();
    
    if (lastRow <= 1) return;
    
    const currentStatus = sheet.getRange(lastRow, STATUS_COLUMN).getValue();
    if (currentStatus && currentStatus.toString().startsWith('http')) return;
    
    // 1. スプレッドシートから文字データを取得して結合
    let textValues = [];
    TEXT_COLUMNS.forEach(col => {
      let val = sheet.getRange(lastRow, col).getValue();
      if (val) textValues.push(val.toString());
    });
    const headerText = textValues.join(' | ');
    
    // 2. 入力されている有効な画像Blobを配列に回収
    let imageBlobs = [];
    IMAGE_URL_COLUMNS.forEach(col => {
      let url = sheet.getRange(lastRow, col).getValue();
      if (url && url.toString().startsWith('http') && !url.toString().includes('drive.google.com')) {
        try {
          let response = UrlFetchApp.fetch(url);
          imageBlobs.push(response.getBlob());
        } catch(err) {
          Logger.log('画像取得エラー (列 ' + col + '): ' + err.message);
        }
      }
    });
    
    if (imageBlobs.length === 0) return;
    
    const totalPages = imageBlobs.length;
    
    // 3. テンプレートスライドをコピーして一時的な作業ファイルを作成
    const templateFile = DriveApp.getFileById(TEMPLATE_SLIDE_ID);
    const tempCopy = templateFile.makeCopy('temp_pdf_work_' + lastRow);
    const presentation = SlidesApp.openById(tempCopy.getId());
    const slides = presentation.getSlides();
    const baseSlide = slides[0]; 
    
    // 4. 各ページ（スライド）を生成し、データを流し込む
    for (let i = totalPages - 1; i >= 0; i--) {
      let targetSlide = baseSlide.duplicate(); 
      
      // テキスト（文字データとページ番号）の置換
      const pageInfo = (i + 1) + ' / ' + totalPages + ' ページ';
      targetSlide.replaceAllText('{{TEXT}}', headerText);
      targetSlide.replaceAllText('{{PAGE}}', pageInfo);
      
      // 画像をスライドに直接挿入
      const img = targetSlide.insertImage(imageBlobs[i]);
// --- 【ここから自動レイアウト調整】 ---
      const maxW = 555;  // 挿入先エリアの最大幅
      const maxH = 700;  // 挿入先エリアの最大高さ
      const targetTop = 100; // 画像の表示開始位置
      const targetLeft = 20; // 左余白
      
      let origW = img.getWidth();
      let origH = img.getHeight();
      
      if (origW > origH) {
        // ◆ 横長画像の場合：90度回転させて縦長にする
        img.setRotation(90);
        
        // 縮小率の計算
        let scale = Math.min(maxW / origH, maxH / origW);
        
        // 【★ここを追加】もし元画像が小さくてscaleが1（等倍）を超える場合は、1固定にして拡大を防ぐ
        if (scale > 1) scale = 1; 
        
        img.setWidth(origW * scale);
        img.setHeight(origH * scale);
        
        // 中央配置の計算
        let centerX = targetLeft + (maxW / 2);
        let centerY = targetTop + (maxH / 2);
        img.setLeft(centerX - (origW * scale) / 2);
        img.setTop(centerY - (origH * scale) / 2);
        
      } else {
        // ◆ 縦長（または正方形）画像の場合：回転させずそのまま配置
        let scale = Math.min(maxW / origW, maxH / origH);
        
        // 【★ここを追加】もし元画像が小さくてscaleが1（等倍）を超える場合は、1固定にして拡大を防ぐ
        if (scale > 1) scale = 1; 
        
        img.setWidth(origW * scale);
        img.setHeight(origH * scale);
        
        // 中央配置の計算
        let left = targetLeft + (maxW - (origW * scale)) / 2;
        let top = targetTop + (maxH - (origH * scale)) / 2;
        img.setLeft(left);
        img.setTop(top);
      }      
    }
    
    // 最初の雛形ページを削除
    baseSlide.remove();
    
    presentation.saveAndClose();
    
    // 5. スライドをPDFとして出力・保存
    const pdfBlob = tempCopy.getAs('application/pdf');
    pdfBlob.setName('Submission_Row' + lastRow + '.pdf');
    
    const folder = DriveApp.getFolderById(DRIVE_FOLDER_ID);
    const pdfFile = folder.createFile(pdfBlob);
    const pdfUrl = pdfFile.getUrl(); 
    
    tempCopy.setTrashed(true); // 一時ファイルの削除
    
    // 6. スプレッドシートにPDFのURLを書き込む
    sheet.getRange(lastRow, STATUS_COLUMN).setValue(pdfUrl);
    
    Logger.log('PDFの作成が完了しました: ' + pdfUrl);
  }
}

// --- デバッグ用コード ---
function debugMain() {
  // 手動テスト用に、擬似的な「イベントオブジェクト」を身代わりで作る
  const dummyEvent = {
    changeType: 'EDIT' // これを入れておくことで本番コードの最初のチェックを突破できます
  };
  
  Logger.log('【デバッグ開始】スプレッドシートの最終行を使ってPDF作成テストを行います。');
  
  // 本番の関数に身代わりのデータを渡して実行
  createPdfFromRow(dummyEvent);
  
  Logger.log('【デバッグ終了】');
}

