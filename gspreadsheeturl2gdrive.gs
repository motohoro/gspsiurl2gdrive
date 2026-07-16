// ==========================================
// 【設定エリア】お使いの環境に合わせて変更してください
// ==========================================
const DRIVE_FOLDER_ID = 'ここにGoogle DriveのフォルダIDを貼り付けます'; 

// 画像URLが書き込まれる「列番号」をすべて [ ] の中に半角カンマ区切りで指定します
// 例：C列（3）、E列（5）、G列（7）が画像項目の場合
const IMAGE_URL_COLUMNS = [3, 5, 7]; 

// 行全体の処理ステータスを記録する列番号（任意・不要なら 0 にしてください）
// 例：H列=8
const STATUS_COLUMN = 8; 
// ==========================================

function saveImagesToDrive(e) {
  // 外部サービスからの「行挿入（INSERT_ROW）」または「編集」を検知
  if (e.changeType === 'INSERT_ROW' || e.changeType === 'EDIT') {
    
    // 外部サービスからの書き込み遅延を考慮し、2秒待機
    Utilities.sleep(2000);
    
    const sheet = SpreadsheetApp.getActiveSpreadsheet().getActiveSheet();
    const lastRow = sheet.getLastRow();
    
    // ヘッダー行（1行目）の場合はスキップ
    if (lastRow <= 1) return;
    
    const folder = DriveApp.getFolderById(DRIVE_FOLDER_ID);
    let processedCount = 0;
    let hasError = false;
    
    // 設定された画像列を1つずつループ処理
    for (let i = 0; i < IMAGE_URL_COLUMNS.length; i++) {
      const colNum = IMAGE_URL_COLUMNS[i];
      const cell = sheet.getRange(lastRow, colNum);
      const url = cell.getValue();
      
      // セルにURLがあり、かつすでにGoogle DriveのURLに変換されていない場合のみ処理
      if (url && url.toString().startsWith('http') && !url.toString().includes('drive.google.com')) {
        try {
          // 1. 画像のダウンロード
          const response = UrlFetchApp.fetch(url);
          const blob = response.getBlob();
          
          // ファイル名の設定（例: L-me_行番号_列番号.拡張子）
          const contentType = blob.getContentType();
          const extension = contentType ? contentType.split('/')[1] : 'jpg';
          blob.setName('L-me_Row' + lastRow + '_Col' + colNum + '.' + extension);
          
          // 2. Google Driveの指定フォルダへ保存
          const file = folder.createFile(blob);
          const fileUrl = file.getUrl(); // 保存したDriveファイルのURL
          
          // 3. 元のスプレッドシートのセルをGoogle DriveのURLに書き換える
          cell.setValue(fileUrl);
          processedCount++;
          
        } catch (error) {
          hasError = true;
          Logger.log('列 ' + colNum + ' の画像保存中にエラーが発生しました: ' + error.message);
        }
      }
    }
    
    // オプション：全体のステータス列の更新
    if (STATUS_COLUMN) {
      const statusCell = sheet.getRange(lastRow, STATUS_COLUMN);
      if (hasError) {
        statusCell.setValue('一部エラーあり');
      } else if (processedCount > 0) {
        statusCell.setValue('全画像 保存完了');
      }
    }
  }
}