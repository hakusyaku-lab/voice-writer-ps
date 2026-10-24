# voice-writer (PowerShell版)
# 音声を文字起こし（ファイル1）し、AIで読みやすく直した改善版（ファイル2）を作るWindows用アプリ。
# https://github.com/hakusyaku-lab/voice-writer-ps
# APIキーはこのファイルに書かないでください（config.json は ドキュメント\音声原稿 に作られます）。
Add-Type -AssemblyName System.Windows.Forms, System.Drawing, System.Speech
[System.Windows.Forms.Application]::EnableVisualStyles()
$utf8 = New-Object Text.UTF8Encoding $true

$docDir = Join-Path ([Environment]::GetFolderPath('MyDocuments')) '音声原稿'
New-Item -ItemType Directory -Force $docDir | Out-Null
$files = @{
  1 = Join-Path $docDir 'ファイル1_文字起こし.txt'
  2 = Join-Path $docDir 'ファイル2_改善版.txt'
}
$configPath = Join-Path $docDir 'config.json'

if (-not (Test-Path $configPath)) { [IO.File]::WriteAllText($configPath, "{`r`n  `"openai_api_key`": `"`",`r`n  `"model`": `"gpt-4o-mini`"`r`n}`r`n", $utf8) }

$bg    = [System.Drawing.Color]::FromArgb(20,18,16)
$paper = [System.Drawing.Color]::FromArgb(27,25,22)
$ink   = [System.Drawing.Color]::FromArgb(235,228,214)
$muted = [System.Drawing.Color]::FromArgb(154,146,134)
$btnC  = [System.Drawing.Color]::FromArgb(37,34,30)
$micC  = [System.Drawing.Color]::FromArgb(215,203,182)
$recC  = [System.Drawing.Color]::FromArgb(196,92,74)
$dark  = [System.Drawing.Color]::FromArgb(26,23,20)
$font  = New-Object System.Drawing.Font('Yu Gothic UI', 12)
$small = New-Object System.Drawing.Font('Yu Gothic UI', 9)

$form = New-Object System.Windows.Forms.Form
$iconPath = Join-Path $PSScriptRoot 'icon.ico'; if (Test-Path $iconPath) { try { $form.Icon = New-Object System.Drawing.Icon($iconPath) } catch {} }
$form.Text = '音声原稿'
$form.Size = New-Object System.Drawing.Size(860, 680)
$form.MinimumSize = New-Object System.Drawing.Size(560, 400)
$form.BackColor = $bg; $form.ForeColor = $ink; $form.StartPosition = 'CenterScreen'; $form.KeyPreview = $true

function New-Bar([string]$dock, [int]$h) {
  $p = New-Object System.Windows.Forms.FlowLayoutPanel
  $p.Dock = $dock; $p.Height = $h; $p.BackColor = $bg; $p.WrapContents = $false
  $p.Padding = New-Object System.Windows.Forms.Padding(8,8,8,4); return $p
}
function New-Btn($bar, $text, $w) {
  $b = New-Object System.Windows.Forms.Button
  $b.Text = $text; $b.Width = $w; $b.Height = 34; $b.Font = $small
  $b.FlatStyle = 'Flat'; $b.BackColor = $btnC; $b.ForeColor = $ink
  $b.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(44,41,36)
  $bar.Controls.Add($b); return $b
}
function New-Lbl($bar, $text) {
  $l = New-Object System.Windows.Forms.Label
  $l.Text = $text; $l.AutoSize = $true; $l.Font = $small; $l.ForeColor = $muted
  $l.Margin = New-Object System.Windows.Forms.Padding(10,9,0,0); $bar.Controls.Add($l); return $l
}

# --- top bar: file switch + speaker
$top = New-Bar 'Top' 50
$rb1 = New-Object System.Windows.Forms.RadioButton; $rb1.Text = 'ファイル1 文字起こし'; $rb1.AutoSize = $true; $rb1.Font = $small; $rb1.ForeColor = $ink; $rb1.Checked = $true; $rb1.Margin = New-Object System.Windows.Forms.Padding(4,8,10,0)
$rb2 = New-Object System.Windows.Forms.RadioButton; $rb2.Text = 'ファイル2 改善版'; $rb2.AutoSize = $true; $rb2.Font = $small; $rb2.ForeColor = $ink; $rb2.Margin = New-Object System.Windows.Forms.Padding(4,8,10,0)
$top.Controls.Add($rb1); $top.Controls.Add($rb2)
[void](New-Lbl $top '発言者')
$spk = New-Object System.Windows.Forms.ComboBox
$spk.Width = 130; $spk.Font = $small; $spk.BackColor = $paper; $spk.ForeColor = $ink
[void]$spk.Items.AddRange(@('話者A','話者B','話者C','（なし）')); $spk.SelectedIndex = 0
$spk.Margin = New-Object System.Windows.Forms.Padding(6,6,0,0)
$top.Controls.Add($spk)
[void](New-Lbl $top 'F2で切替／名前は直接入力可')

# --- editor
$tb = New-Object System.Windows.Forms.TextBox
$tb.Multiline = $true; $tb.ScrollBars = 'Vertical'; $tb.AcceptsReturn = $true; $tb.WordWrap = $true
$tb.Font = $font; $tb.BackColor = $paper; $tb.ForeColor = $ink; $tb.BorderStyle = 'None'; $tb.Dock = 'Fill'

$interim = New-Object System.Windows.Forms.Label
$interim.Dock = 'Bottom'; $interim.Height = 26; $interim.Font = $small
$interim.ForeColor = [System.Drawing.Color]::FromArgb(201,184,150); $interim.Padding = New-Object System.Windows.Forms.Padding(8,4,8,0)

# --- bottom bar
$bar = New-Bar 'Bottom' 54
$mic   = New-Btn $bar '🎤 話す' 110; $mic.BackColor = $micC; $mic.ForeColor = $dark
$improve = New-Btn $bar '改善版を作る' 110
$copy  = New-Btn $bar 'コピー' 80
$open  = New-Btn $bar 'フォルダ' 80
$clear = New-Btn $bar 'クリア' 80
$status = New-Lbl $bar '待機中'
$count  = New-Lbl $bar ''

$form.Controls.Add($tb); $form.Controls.Add($interim); $form.Controls.Add($bar); $form.Controls.Add($top)

$script:cur = 1
$script:loading = $false
function Load-File($n) {
  $script:loading = $true
  $script:cur = $n
  $tb.Text = if (Test-Path $files[$n]) { [IO.File]::ReadAllText($files[$n], [Text.Encoding]::UTF8) } else { '' }
  $tb.SelectionStart = $tb.TextLength; $tb.ScrollToCaret()
  $script:loading = $false
  Update-Count
}
function Save-Cur { try { [IO.File]::WriteAllText($files[$script:cur], $tb.Text, $utf8) } catch {} }
function Update-Count { $count.Text = ('ファイル{0}　{1:N0} 文字' -f $script:cur, $tb.TextLength) }
$tb.Add_TextChanged({ if (-not $script:loading) { Save-Cur }; Update-Count })
$rb1.Add_CheckedChanged({ if ($rb1.Checked) { Save-Cur; Load-File 1 } })
$rb2.Add_CheckedChanged({ if ($rb2.Checked) { Save-Cur; Load-File 2 } })
Load-File 1

$form.Add_KeyDown({ param($s,$e)
  if ($e.KeyCode -eq 'F2') { $spk.SelectedIndex = ($spk.SelectedIndex + 1) % $spk.Items.Count; $status.Text = '発言者: ' + $spk.Text; $e.Handled = $true }
})

# --- speech
$script:engine = $null; $script:listening = $false; $script:initErr = ''
function Init-Engine {
  if ($script:engine) { return $true }
  try {
    $rec = [System.Speech.Recognition.SpeechRecognitionEngine]::InstalledRecognizers() | Where-Object { $_.Culture.Name -eq 'ja-JP' } | Select-Object -First 1
    if (-not $rec) { throw '日本語(ja-JP)の音声認識エンジンが見つかりません。設定→時刻と言語→言語で日本語の「音声認識」を追加してください。' }
    $eng = New-Object System.Speech.Recognition.SpeechRecognitionEngine $rec
    try { $eng.SetInputToDefaultAudioDevice() } catch {
      throw ("既定の録音デバイスを開けません（" + $_.Exception.InnerException.Message + $_.Exception.Message + "）。`r`n設定→サウンド→入力で、使うマイク（例: TP35 Pro）を既定にしてください。")
    }
    $eng.LoadGrammar((New-Object System.Speech.Recognition.DictationGrammar))
    $eng.BabbleTimeout = [TimeSpan]::FromSeconds(0)
    $eng.EndSilenceTimeout = [TimeSpan]::FromMilliseconds(800)
    $engine = $eng
    $engine.Add_SpeechHypothesized({ param($s,$e) $interim.Text = 'いま（' + $spk.Text + '）　' + $e.Result.Text })
    $engine.Add_SpeechRecognized({ param($s,$e)
      $interim.Text = ''
      # low-confidence results are kept (no drop)
      $t = ($e.Result.Text -replace '改行', "`r`n" -replace '句点', '。' -replace '読点', '、').Trim(" `t　")
      if (-not $t) { return }
      $now = Get-Date
      if ($t -eq $script:lastText -and ($now - $script:lastAt).TotalMilliseconds -lt 1600) { return }
      $script:lastText = $t; $script:lastAt = $now
      if (-not $rb1.Checked) { $rb1.Checked = $true }
      $who = $spk.Text
      $tb.SelectionStart = $tb.TextLength
      if ($who -ne '（なし）' -and $who -ne $script:lastSpk) {
        $prefix = if ($tb.TextLength -gt 0 -and -not $tb.Text.EndsWith("`n")) { "`r`n" } else { '' }
        $tb.SelectedText = $prefix + '[' + (Get-Date -Format 'HH:mm') + '] ' + $who + '：'
        $script:lastSpk = $who
      }
      $tb.SelectedText = $t
      $tb.ScrollToCaret()
    })
    $engine.Add_AudioSignalProblemOccurred({ param($s,$e) if ($script:listening) { $status.Text = '聞いています…（' + $e.AudioSignalProblem + '）' } })
    $engine.Add_AudioLevelUpdated({ param($s,$e) if ($script:listening) { $status.Text = '聞いています… 音量 ' + ('|' * [int]($e.AudioLevel / 10)) } })
    $engine.Add_RecognizeCompleted({ param($s,$e) if ($script:listening) { try { $s.RecognizeAsync([System.Speech.Recognition.RecognizeMode]::Multiple) } catch {} } })
    $script:engine = $eng; $script:initErr = ''; return $true
  } catch { $script:engine = $null; $script:initErr = $_.Exception.Message; return $false }
}
$spk.Add_SelectedIndexChanged({ $script:lastSpk = '' })
$spk.Add_TextChanged({ $script:lastSpk = '' })
$script:lastText = ''; $script:lastAt = [DateTime]::MinValue; $script:lastSpk = ''
[void](Init-Engine)
if ($script:initErr) { $status.Text = 'マイク未接続：🎤を押すと再試行します' }

$mic.Add_Click({
  if (-not (Init-Engine)) {
    $r = [System.Windows.Forms.MessageBox]::Show("音声認識を開始できません。`r`n`r`n" + $script:initErr + "`r`n`r`nサウンド設定を開きますか？（マイクのプライバシー設定も確認してください）", '音声原稿', 'YesNo', 'Warning')
    if ($r -eq 'Yes') { Start-Process 'ms-settings:sound'; Start-Process 'ms-settings:privacy-microphone' }
    return
  }
  $engine = $script:engine
  if ($script:listening) {
    $script:listening = $false; $engine.RecognizeAsyncCancel()
    $mic.Text = '🎤 話す'; $mic.BackColor = $micC; $mic.ForeColor = $dark; $status.Text = '待機中'; $interim.Text = ''
  } else {
    $rb1.Checked = $true; $script:lastSpk = ''
    try { $engine.SetInputToDefaultAudioDevice(); $engine.RecognizeAsync([System.Speech.Recognition.RecognizeMode]::Multiple) }
    catch { $script:engine = $null; [System.Windows.Forms.MessageBox]::Show("マイクを開けません：" + $_.Exception.Message + "`r`n設定→サウンド→入力で既定のマイクを確認してください。", '音声原稿') | Out-Null; return }
    $script:listening = $true
    $mic.Text = '■ 停止'; $mic.BackColor = $recC; $mic.ForeColor = [System.Drawing.Color]::White; $status.Text = '聞いています…'
  }
})


# --- file 2 (needs API key, see README)
$improve.Add_Click({
  $cfg = $null; try { $cfg = Get-Content $configPath -Raw -Encoding UTF8 | ConvertFrom-Json } catch {}
  $apiKey = if ($env:OPENAI_API_KEY) { $env:OPENAI_API_KEY } elseif ($cfg) { $cfg.openai_api_key } else { '' }
  if (-not $apiKey) {
    [System.Windows.Forms.MessageBox]::Show("ファイル2（改善版）を作るにはAPIキーの導入が必要です。`r`nREADME の「ファイル2：改善版」を見て、config.json か環境変数 OPENAI_API_KEY にAPIキーを設定してください。`r`n`r`nconfig.json の場所: $configPath", '音声原稿') | Out-Null
    Start-Process notepad $configPath; return
  }
  Save-Cur
  $src = if (Test-Path $files[1]) { [IO.File]::ReadAllText($files[1], [Text.Encoding]::UTF8) } else { '' }
  if (-not $src.Trim()) { $status.Text = 'ファイル1が空です'; return }
  $status.Text = '改善版を作成中…'; $form.Refresh()
  try {
    $model = if ($cfg -and $cfg.model) { $cfg.model } else { 'gpt-4o-mini' }
    $body = @{ model = $model; messages = @(
      @{ role = 'system'; content = '音声の文字起こしを、意味を変えずに読みやすい日本語に整えてください。誤変換・言い間違い・フィラー（えー、あの等）を直し、句読点と段落を整えます。「[時刻] 発言者：」の行頭表記は残してください。整えた本文だけを出力してください。' },
      @{ role = 'user'; content = $src }) } | ConvertTo-Json -Depth 5
    $res = Invoke-RestMethod -Uri 'https://api.openai.com/v1/chat/completions' -Method Post -Headers @{ Authorization = 'Bearer ' + $apiKey } -ContentType 'application/json; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes($body))
    [IO.File]::WriteAllText($files[2], $res.choices[0].message.content, $utf8)
    if ($rb2.Checked) { Load-File 2 } else { $rb2.Checked = $true }
    $status.Text = 'ファイル2を作成しました'
  } catch { $status.Text = '作成に失敗しました'; [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, '音声原稿') | Out-Null }
})

$copy.Add_Click({ if ($tb.TextLength -gt 0) { [System.Windows.Forms.Clipboard]::SetText($tb.Text); $status.Text = 'コピーしました' } })
$open.Add_Click({ Start-Process explorer $docDir })
$clear.Add_Click({
  if ($tb.TextLength -eq 0) { return }
  if ([System.Windows.Forms.MessageBox]::Show(('ファイル{0}をすべて消しますか？' -f $script:cur), '音声原稿', 'YesNo') -eq 'Yes') { $tb.Clear(); $script:lastSpk = ''; $status.Text = 'クリアしました' }
})
$form.Add_FormClosing({ Save-Cur; if ($script:engine) { try { $script:listening = $false; $script:engine.RecognizeAsyncCancel(); $script:engine.Dispose() } catch {} } })
[System.Windows.Forms.Application]::Run($form)
