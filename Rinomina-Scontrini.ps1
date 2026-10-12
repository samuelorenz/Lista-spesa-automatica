# Legge le foto in Scontrini\Nuovi con l'OCR di Windows e le archivia come "Negozio_AAAA-MM-GG".
# Più foto dello stesso scontrino (scontrini lunghi) vengono riconosciute e UNITE in un solo scontrino,
# senza duplicare le righe. Stato salvato in Scontrini\archivio.json.
#   Archiviati\       scontrini completi (negozio + data letti): Lidl_2026-10-12.jpg / Lidl_2026-10-12_p1.jpg, _p2.jpg ...
#   Da controllare\   negozio o data mancanti (possono completarsi se arriva un'altra foto dello stesso scontrino)
#   Duplicati\        foto identiche a una già ricevuta
# Uso:  powershell -File Rinomina-Scontrini.ps1          (una volta)
#       powershell -File Rinomina-Scontrini.ps1 -Watch   (resta in ascolto)
param([switch]$Watch)

$root = Join-Path $PSScriptRoot 'Scontrini'
$new  = Join-Path $root 'Nuovi'
$done = Join-Path $root 'Archiviati'
$chk  = Join-Path $root 'Da controllare'
$dupD = Join-Path $root 'Duplicati'
$stateFile = Join-Path $root 'archivio.json'
foreach ($d in $new,$done,$chk,$dupD) { New-Item -ItemType Directory -Force $d | Out-Null }
$inv = [Globalization.CultureInfo]::InvariantCulture

Add-Type -AssemblyName System.Runtime.WindowsRuntime
$null = [Windows.Media.Ocr.OcrEngine,Windows.Media.Ocr,ContentType=WindowsRuntime]
$null = [Windows.Graphics.Imaging.BitmapDecoder,Windows.Graphics.Imaging,ContentType=WindowsRuntime]
$null = [Windows.Storage.StorageFile,Windows.Storage,ContentType=WindowsRuntime]
$null = [Windows.Globalization.Language,Windows.Globalization,ContentType=WindowsRuntime]

$asTask = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
  $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' })[0]
function Await($op, $type) {
  $t = $asTask.MakeGenericMethod($type).Invoke($null, @($op)); $t.Wait(-1) | Out-Null; $t.Result
}

$ocr = [Windows.Media.Ocr.OcrEngine]::TryCreateFromLanguage([Windows.Globalization.Language]::new('it-IT'))
if (-not $ocr) { $ocr = [Windows.Media.Ocr.OcrEngine]::TryCreateFromUserProfileLanguages() }

# Catene note: parola chiave nello scontrino -> nome file
$stores = [ordered]@{
  'esselunga'='Esselunga'; 'conad'='Conad'; 'coop'='Coop'; 'lidl'='Lidl'; 'eurospin'='Eurospin'; 'carrefour'='Carrefour'
  'md '='MD'; 'penny'='Penny'; 'aldi'='Aldi'; 'pam'='Pam'; 'panorama'='Pam'; 'iper'='Iper'; 'despar'='Despar'; 'eurospar'='Despar'
  'interspar'='Despar'; 'tigros'='Tigros'; 'famila'='Famila'; 'bennet'='Bennet'; 'in''s'='Ins'; 'ins mercato'='Ins'
  'dok'='Dok'; 'sigma'='Sigma'; 'todis'='Todis'; 'prix'='Prix'; 'unes'='Unes'; 'il gigante'='IlGigante'; 'ipercoop'='Coop'
  'naturasi'='NaturaSi'; 'decathlon'='Decathlon'; 'tigotà'='Tigota'; 'acqua e sapone'='AcquaESapone'
}
# righe che non sono prodotti (gli sconti restano: servono a far tornare il totale)
$ignoreRe = '(?i)^(totale|subtotale|sub-totale|resto\b|contanti|carta\s*(di|cred|banc|fid|insieme)|bancomat|pagamento|iva\b|importo|punti|arrotond|ticket|tel\b|p\.?\s?iva|cod\b|data\b|ora\b|scontrino|cassa|operatore|grazie|documento|imponibile|pezzi|articoli|card\b|saldo|elettronic|di cui|buono|rt\b|descrizione|prezzo)'

# ---------- OCR e riconoscimento ----------
$null = [Windows.Graphics.Imaging.BitmapTransform,Windows.Graphics.Imaging,ContentType=WindowsRuntime]

# Lo scontrino è a colonne (nome | IVA | prezzo): l'OCR le restituisce come blocchi separati.
# Ricostruisco le righe dalle posizioni delle parole: correggo l'inclinazione della foto e
# raggruppo le parole con la stessa altezza.
function Rows-FromOcr($res) {
  $words = @()
  $slopes = @()
  foreach ($ln in $res.Lines) {
    $ws = @($ln.Words)
    foreach ($w in $ws) { $r = $w.BoundingRect; $words += [pscustomobject]@{ t = $w.Text; x = $r.X + $r.Width/2; y = $r.Y + $r.Height/2; h = $r.Height } }
    if ($ws.Count -ge 2) {
      $a = $ws[0].BoundingRect; $b = $ws[$ws.Count-1].BoundingRect; $dx = ($b.X + $b.Width/2) - ($a.X + $a.Width/2)
      if ([Math]::Abs($dx) -gt 150) { $slopes += [pscustomobject]@{ y = ($a.Y + $b.Y)/2; s = (($b.Y + $b.Height/2) - ($a.Y + $a.Height/2)) / $dx } }
    }
  }
  if (-not $words.Count) { return '' }
  $hs = @($words | ForEach-Object { $_.h } | Sort-Object); $tol = 0.45 * $hs[[int]($hs.Count/2)]
  # l'inclinazione cambia lungo lo scontrino (carta incurvata): per ogni parola uso la mediana
  # delle inclinazioni delle 15 righe più vicine in verticale, riferita a una colonna comune
  $xs = @($words | ForEach-Object { $_.x } | Sort-Object); $xref = $xs[[int]($xs.Count/2)]
  foreach ($w in $words) {
    $s = 0
    if ($slopes.Count) {
      $near = @($slopes | Sort-Object { [Math]::Abs($_.y - $w.y) } | Select-Object -First 15 | ForEach-Object { $_.s } | Sort-Object)
      $s = $near[[int]($near.Count/2)]
    }
    $w.y = $w.y - $s * ($w.x - $xref)
  }
  $words = @($words | Sort-Object y)
  $rows = @(); $cur = @($words[0]); $cy = $words[0].y
  foreach ($w in ($words | Select-Object -Skip 1)) {
    if (($w.y - $cy) -le $tol) { $cur += $w; $cy = ($cur | Measure-Object y -Average).Average }
    else { $rows += (($cur | Sort-Object x | ForEach-Object { $_.t }) -join ' '); $cur = @($w); $cy = $w.y }
  }
  $rows += (($cur | Sort-Object x | ForEach-Object { $_.t }) -join ' ')
  $rows -join "`n"
}

# prova le 4 rotazioni (foto girate di lato) e tiene quella che "legge" più prezzi
function Read-Text($file) {
  $sf  = Await ([Windows.Storage.StorageFile]::GetFileFromPathAsync($file)) ([Windows.Storage.StorageFile])
  $st  = Await ($sf.OpenAsync([Windows.Storage.FileAccessMode]::Read)) ([Windows.Storage.Streams.IRandomAccessStream])
  $dec = Await ([Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync($st)) ([Windows.Graphics.Imaging.BitmapDecoder])
  $best = ''; $bestScore = -1
  foreach ($rot in 'None','Clockwise90Degrees','Clockwise270Degrees','Clockwise180Degrees') {
    $tr = New-Object Windows.Graphics.Imaging.BitmapTransform
    $tr.Rotation = [Windows.Graphics.Imaging.BitmapRotation]::$rot
    $bmp = Await ($dec.GetSoftwareBitmapAsync([Windows.Graphics.Imaging.BitmapPixelFormat]::Bgra8, [Windows.Graphics.Imaging.BitmapAlphaMode]::Premultiplied, $tr, [Windows.Graphics.Imaging.ExifOrientationMode]::IgnoreExifOrientation, [Windows.Graphics.Imaging.ColorManagementMode]::DoNotColorManage)) ([Windows.Graphics.Imaging.SoftwareBitmap])
    $res  = Await ($ocr.RecognizeAsync($bmp)) ([Windows.Media.Ocr.OcrResult])
    $text = Rows-FromOcr $res
    $score = [regex]::Matches($text, '\d\s*[.,]\s*\d{2}\b').Count + 0.05 * [regex]::Matches($text, '\p{L}{4,}').Count
    if ($score -gt $bestScore) { $best = $text; $bestScore = $score }
    if ($bestScore -ge 8) { break }
  }
  $st.Dispose()
  $best
}

function Find-Store($text) {
  # prima l'intestazione (prime righe), poi tutto il testo; la parola deve iniziare la parola (evita "pam" in "pampers")
  $lines = @($text -split "`n")
  foreach ($chunk in @(($lines | Select-Object -First 10) -join ' ', $text)) {
    $low = ' ' + $chunk.ToLower() + ' '
    foreach ($k in $stores.Keys) { if ($low -match ('(?<![\p{L}\p{N}])' + [regex]::Escape($k))) { return $stores[$k] } }
  }
  # catena sconosciuta: prima riga dell'intestazione, solo se la foto sembra contenerla (P.IVA / via nelle prime righe)
  $first = @($text -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ } | Select-Object -First 8)
  if (($first -join ' ') -match '(?i)p\.?\s?iva|partita iva|\bvia\b|\bviale\b|\bpiazza\b') {
    $c = ($first[0] -replace '[^\p{L}\p{N} ]','').Trim()
    if ($c.Length -ge 4 -and $first[0] -notmatch '\d+[.,]\d{2}\s*$') { return (($c -split ' ' | Select-Object -First 2) -join '') }
  }
  $null
}

function Find-Date($text) {
  foreach ($m in [regex]::Matches($text, '(?<!\d)(\d{1,2})[/.\-](\d{1,2})[/.\-](\d{4}|\d{2})(?!\d)')) {
    $d = [int]$m.Groups[1].Value; $mo = [int]$m.Groups[2].Value; $y = [int]$m.Groups[3].Value
    if ($y -lt 100) { $y += 2000 }
    if ($d -ge 1 -and $d -le 31 -and $mo -ge 1 -and $mo -le 12 -and $y -ge 2000 -and $y -le (Get-Date).Year + 1) {
      return ('{0:0000}-{1:00}-{2:00}' -f $y,$mo,$d)
    }
  }
  $null
}

function KeyName($s) { ($s.ToLower() -replace '[^\p{L}\p{N}]','') }

function Parse-Receipt($text) {
  $time = $null
  $m = [regex]::Match($text, '(?<!\d)([01]?\d|2[0-3]):([0-5]\d)(?!\d)')
  if ($m.Success) { $time = '{0:00}:{1}' -f [int]$m.Groups[1].Value, $m.Groups[2].Value }
  $doc = $null
  $m = [regex]::Match($text, '(?i)\b(?:documento|doc\.?|scontrino)\s*(?:n[°o.]*)?\s*[:\-]?\s*(\d{1,4}[-/]\d{1,6}|\d{3,8})\b')
  if ($m.Success) { $doc = $m.Groups[1].Value -replace '\D','' }
  # "- 1 , 99" -> "-1,99" (l'OCR a volte stacca i numeri)
  # e "-o,19" (o al posto di 0) -> "-0,19" se è un prezzo a fine riga
  $fixO = [regex]'(?<![\p{L}])(-?)([\dOo]{1,3})\s*([.,])\s*([\dOo]{2})(-?)\s*$'
  $text = (($text -split "`n") | ForEach-Object {
    $l0 = $_ -replace '(\d)\s+([.,])\s*(\d{2})(?!\d)','$1$2$3' -replace '(\d)\s*([.,])\s+(\d{2})(?!\d)','$1$2$3' -replace '-\s+(\d)','-$1'
    $mo = $fixO.Match($l0)
    if ($mo.Success -and (($mo.Groups[2].Value + $mo.Groups[4].Value) -match '\d')) {
      $l0 = $l0.Substring(0, $mo.Index) + $mo.Groups[1].Value + ($mo.Groups[2].Value -replace '[Oo]','0') + $mo.Groups[3].Value + ($mo.Groups[4].Value -replace '[Oo]','0') + $mo.Groups[5].Value
    }
    $l0 }) -join "`n"
  $total = $null; $sub = $null; $lines = @(); $stop = $false; $pq = $null
  foreach ($raw in ($text -split "`n")) {
    $l = $raw.Trim(); if (-not $l -or $stop) { continue }
    if ($l -match '(?i)^dettaglio') { $stop = $true; continue }      # riepilogo sconti/pagamenti: non sono righe da contare
    if ($l -match '(?i)^\W*totale\b' -and $l -notmatch '(?i)subtotale|resto' -and -not $total) {
      $mm = [regex]::Matches($l, '\d+[.,]\d{2}'); if ($mm.Count) { $total = ($mm[$mm.Count-1].Value -replace ',','.'); $stop = $true }
      continue
    }
    if ($l -match '^\s*(\d+)\s*[xX*]\s*\d+[.,]\d{2}\s*$') { $pq = [int]$Matches[1]; continue }   # riga "2 x 5,99" sopra il prodotto
    if ($l -match '(?i)^sub-?totale') {                                                              # ripiego se il "TOTALE" non si legge
      $mm = [regex]::Matches($l, '\d+[.,]\d{2}'); if ($mm.Count) { $sub = ($mm[$mm.Count-1].Value -replace ',','.') }
      continue
    }
    # "Offerta 2X1" senza importo letto: vale la metà della riga prodotto sopra
    if ($l -match '(?i)^offerta\s*2\s*x\s*[1lI]\s*$' -and $lines.Count -and [decimal]::Parse($lines[-1].p, $inv) -gt 0) {
      $d = [Math]::Round([decimal]::Parse($lines[-1].p, $inv) / 2, 2)
      $lines += [pscustomobject]@{ t = ('Offerta 2X1 -' + $d.ToString('0.00', $inv).Replace('.', ',')); n = 'offerta2x1'; p = (-$d).ToString('0.00', $inv) }
      continue
    }
    $m = [regex]::Match($l, '(-?)(\d+[.,]\d{2})(-?)\s*[A-Za-z]?\s*$')
    if (-not $m.Success) { continue }
    $name = $l.Substring(0, $m.Index).Trim()
    if ($name -match $ignoreRe -or $l -match '(?i)\btotale\b') { continue }
    $name = ($name -replace '\s+[\dOo]{1,2}\s*[.,]\s*[0Oo]{2}\s*[%xX*]\s*$','' -replace '^\d+\s*[x*]\s*','').Trim()   # colonna IVA e quantità
    if ([regex]::Matches($name, '\p{L}').Count -lt 3) { continue }
    $neg = $m.Groups[1].Value -or $m.Groups[3].Value
    $p = [decimal]::Parse(($m.Groups[2].Value -replace ',','.'), $inv)
    if ($neg) { $p = -$p }
    $price = ($(if ($neg) { '-' } else { '' }) + $m.Groups[2].Value)
    $t = if ($pq -and -not $neg) { "$pq x $name $price" } else { "$name $price" }
    $pq = $null
    $lines += [pscustomobject]@{ t = $t; n = (KeyName $name); p = $p.ToString('0.00', $inv) }
  }
  if (-not $total -and $sub) { $total = $sub }
  [pscustomobject]@{ id=''; store=(Find-Store $text); date=(Find-Date $text); time=$time; doc=$doc; total=$total
                     lines=$lines; files=@(); orig=''; base=''; txt='' }
}

# ---------- confronto righe / unione ----------
function Lev([string]$a, [string]$b) {
  if ($a -eq $b) { return 0 }
  $n = $a.Length; $m = $b.Length; if ($n -eq 0) { return $m }; if ($m -eq 0) { return $n }
  $prev = 0..$m
  for ($i = 1; $i -le $n; $i++) {
    $cur = New-Object int[] ($m+1); $cur[0] = $i
    for ($j = 1; $j -le $m; $j++) {
      $cost = if ($a[$i-1] -eq $b[$j-1]) { 0 } else { 1 }
      $cur[$j] = [Math]::Min([Math]::Min($cur[$j-1]+1, $prev[$j]+1), $prev[$j-1]+$cost)
    }
    $prev = $cur
  }
  $prev[$m]
}
# stessa riga = stesso prezzo e nome quasi uguale (tollera piccoli errori di OCR)
function LineEq($a, $b) {
  if ($a.p -ne $b.p) { return $false }
  $tol = [Math]::Max(2, [Math]::Floor([Math]::Max($a.n.Length, $b.n.Length) * 0.3))
  (Lev $a.n $b.n) -le $tol
}
function Run-Eq($x, $xs, $y, $ys, $k) {   # x[xs..xs+k-1] == y[ys..ys+k-1]
  for ($i = 0; $i -lt $k; $i++) { if (-not (LineEq $x[$xs+$i] $y[$ys+$i])) { return $false } }
  $true
}
# unione per sovrapposizione contigua (>=2 righe): contenuta / coda di A = testa di B / coda di B = testa di A
function Merge-Seq($A, $B) {
  $A = @($A); $B = @($B)
  if ($A.Count -lt 2 -or $B.Count -lt 2) { return $null }
  foreach ($pair in @(@($A,$B),@($B,$A))) {
    $s = $pair[0]; $l = $pair[1]
    if ($s.Count -le $l.Count) { for ($o = 0; $o -le $l.Count - $s.Count; $o++) { if (Run-Eq $s 0 $l $o $s.Count) { return ,$l } } }
  }
  $max = [Math]::Min($A.Count, $B.Count)
  for ($k = $max; $k -ge 1; $k--) {
    # con una sola riga in comune (l'OCR può perderne qualcuna) mi fido solo se è unica in entrambe le foto
    if ($k -eq 1) {
      $cnt = 0; foreach ($x in $A) { if (LineEq $x $B[0]) { $cnt++ } }; foreach ($x in $B) { if (LineEq $x $A[$A.Count-1]) { $cnt++ } }
      $cnt2 = 0; foreach ($x in $A) { if (LineEq $x $B[$B.Count-1]) { $cnt2++ } }; foreach ($x in $B) { if (LineEq $x $A[0]) { $cnt2++ } }
    }
    if (Run-Eq $A ($A.Count-$k) $B 0 $k) {
      if ($k -ge 2 -or $cnt -eq 2) { return ,(@($A) + @($B | Select-Object -Skip $k)) }
    }
    if (Run-Eq $B ($B.Count-$k) $A 0 $k) {
      if ($k -ge 2 -or $cnt2 -eq 2) { return ,(@($B) + @($A | Select-Object -Skip $k)) }
    }
  }
  $null
}
# unione tollerante: sequenza comune più lunga (LCS) delle righe uguali; tra due righe in comune,
# se le foto leggono diversamente lo stesso tratto tengo la lettura con più righe (l'altra ne ha perse o fuse)
function Merge-Lcs($A, $B) {
  $A = @($A); $B = @($B); $n = $A.Count; $m = $B.Count
  if ($n -lt 3 -or $m -lt 3) { return $null }
  $eq = New-Object 'bool[,]' $n, $m
  for ($i = 0; $i -lt $n; $i++) { for ($j = 0; $j -lt $m; $j++) { if ($A[$i].p -eq $B[$j].p) { $eq[$i,$j] = (LineEq $A[$i] $B[$j]) } } }
  $L = New-Object 'int[,]' ($n+1), ($m+1)
  for ($i = $n-1; $i -ge 0; $i--) {
    for ($j = $m-1; $j -ge 0; $j--) {
      $i1 = $i + 1; $j1 = $j + 1
      if ($eq[$i,$j]) { $L[$i,$j] = $L[$i1,$j1] + 1 }
      else { $down = $L[$i1,$j]; $right = $L[$i,$j1]; $L[$i,$j] = [Math]::Max($down, $right) }
    }
  }
  if ($L[0,0] -lt 3) { return $null }
  $out = @(); $i = 0; $j = 0; $ia = 0; $jb = 0
  while ($i -lt $n -and $j -lt $m) {
    $i1 = $i + 1; $j1 = $j + 1
    if ($eq[$i,$j] -and $L[$i,$j] -eq $L[$i1,$j1] + 1) {
      $ga = @($A | Select-Object -Skip $ia -First ($i-$ia)); $gb = @($B | Select-Object -Skip $jb -First ($j-$jb))
      $out += $(if ($gb.Count -gt $ga.Count) { $gb } else { $ga })
      $out += $A[$i]; $i++; $j++; $ia = $i; $jb = $j
    } elseif ($L[$i1,$j] -ge $L[$i,$j1]) { $i++ } else { $j++ }
  }
  $ga = @($A | Select-Object -Skip $ia); $gb = @($B | Select-Object -Skip $jb)
  $out += $(if ($gb.Count -gt $ga.Count) { $gb } else { $ga })
  ,$out
}
# ripiego (OCR ha perso una riga): ogni riga di A "annulla" al più una riga uguale di B
function Merge-Multi($A, $B) {
  $A = @($A); $B = @($B); $used = @{}; $add = @(); $shared = 0
  foreach ($nl in $B) {
    $hit = -1
    for ($j = 0; $j -lt $A.Count; $j++) { if (-not $used.ContainsKey($j) -and (LineEq $A[$j] $nl)) { $hit = $j; break } }
    if ($hit -ge 0) { $used[$hit] = $true; $shared++ } else { $add += $nl }
  }
  [pscustomobject]@{ lines = (@($A) + $add); shared = $shared }
}
function Same($a, $b) { $a -and $b -and ($a -eq $b) }
function Compat($x, $y) {
  foreach ($f in 'store','date','time','doc') {
    if ($x.$f -and $y.$f -and ($x.$f -ne $y.$f)) { return $false }
  }
  $true
}
function Strong($x, $y) {
  (Same $x.doc $y.doc) -or ((Same $x.store $y.store) -and (Same $x.date $y.date) -and (Same $x.time $y.time))
}
# ritorna le righe unite se X e Y sono lo stesso scontrino, altrimenti $null
function Try-Merge($x, $y) {
  if (-not (Compat $x $y)) { return $null }
  $seq = Merge-Seq $x.lines $y.lines
  if ($null -ne $seq) { return ,@($seq) }
  $lcs = Merge-Lcs $x.lines $y.lines
  if ($null -ne $lcs) { return ,@($lcs) }
  $multi = Merge-Multi $x.lines $y.lines
  if ($multi.shared -ge 2 -or (Strong $x $y)) { return ,@($multi.lines) }
  $null
}
function Absorb($x, $y, $lines) {
  foreach ($f in 'store','date','time','doc','total') { if (-not $x.$f -and $y.$f) { $x.$f = $y.$f } }
  $x.files = @($x.files) + @($y.files)
  $x.lines = @($lines)
}

function Check-Total($r) {
  $sum = [decimal]0; foreach ($l in @($r.lines)) { $sum += [decimal]::Parse($l.p, $inv) }
  if (-not $r.total) { return "totale non letto (somma righe $($sum.ToString('0.00',$inv)))" }
  $t = [decimal]::Parse($r.total, $inv); $diff = $t - $sum
  if ([Math]::Abs($diff) -lt 0.005) { return "OK: somma righe = totale $($t.ToString('0.00',$inv))" }
  "ATTENZIONE: totale $($t.ToString('0.00',$inv)) ma somma righe $($sum.ToString('0.00',$inv)) (differenza $($diff.ToString('0.00',$inv)): righe mancanti o foto da aggiungere?)"
}

# ---------- archivio / file ----------
function Load-State {
  if (Test-Path $stateFile) {
    try {
      $s = Get-Content $stateFile -Raw -Encoding UTF8 | ConvertFrom-Json
      if ($s) {
        $s.hashes = [object[]]@($s.hashes | Where-Object { $_ })
        $s.receipts = [object[]]@($s.receipts | Where-Object { $_ })
        foreach ($r in $s.receipts) { $r.files = [object[]]@($r.files | Where-Object { $_ }); $r.lines = [object[]]@($r.lines | Where-Object { $_ }) }
        return $s
      }
    } catch { Write-Warning "archivio.json illeggibile, riparto da zero: $($_.Exception.Message)" }
  }
  [pscustomobject]@{ hashes = @(); receipts = @() }
}
function Save-State { ConvertTo-Json -InputObject $script:state -Depth 6 | Set-Content $stateFile -Encoding UTF8 }

function Build-Txt($r) {
  $h = @("# Negozio: $($r.store)", "# Data: $($r.date) $($r.time)", "# Foto: $(@($r.files).Count)")
  $h + @($r.lines | ForEach-Object { $_.t }) + @("# Controllo: $(Check-Total $r)")
}

# rinomina/sposta tutte le foto dello scontrino e riscrive il .txt
function Place-Receipt($r) {
  $r.files = [object[]]@($r.files | Where-Object { Test-Path -LiteralPath $_ })
  $complete = $r.store -and $r.date
  $dir = if ($complete) { $done } else { $chk }
  if ($complete) { $base = "$($r.store)_$($r.date)"; if ($r.time) { $base += '_' + ($r.time -replace ':','') } }
  else { $base = 'DaControllare_' + $r.orig }
  $cand = $base; $i = 2
  while (@($script:state.receipts | Where-Object { $_.id -ne $r.id -and $_.base -eq $cand }).Count) { $cand = "${base}_r$i"; $i++ }
  $r.base = $cand
  $multi = @($r.files).Count -gt 1
  $plan = @(); $k = 1
  foreach ($f in $r.files) {
    $ext = [IO.Path]::GetExtension($f).ToLower()
    $name = if ($multi) { "${cand}_p$k$ext" } else { "$cand$ext" }; $k++
    $plan += [pscustomobject]@{ src = $f; dest = (Join-Path $dir $name); tmp = $null }
  }
  # due fasi, così gli spostamenti non si sovrascrivono a vicenda
  foreach ($p in $plan) { if ($p.src -ne $p.dest) { $p.tmp = Join-Path $dir ("~" + [guid]::NewGuid().ToString('N') + [IO.Path]::GetExtension($p.src)); Move-Item -LiteralPath $p.src -Destination $p.tmp } }
  foreach ($p in $plan) { if ($p.tmp) { Move-Item -LiteralPath $p.tmp -Destination $p.dest -Force } }
  $r.files = [object[]]@($plan | ForEach-Object { $_.dest })
  if ($r.txt -and (Test-Path -LiteralPath $r.txt)) { Remove-Item -LiteralPath $r.txt -Force }
  $r.txt = Join-Path $dir "$cand.txt"
  Set-Content -LiteralPath $r.txt -Value (Build-Txt $r) -Encoding UTF8
}

function Process-All {
  $imgs = @(Get-ChildItem $new -File | Where-Object { $_.Extension -match '^\.(jpe?g|png|bmp|tiff?|webp)$' } | Sort-Object LastWriteTime)
  if (-not $imgs.Count) { return }
  $script:state = Load-State
  foreach ($f in $imgs) {
    try {
      $hash = (Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash
      if ($script:state.hashes -contains $hash) {
        $dest = Join-Path $dupD ($f.BaseName + '_' + $hash.Substring(0,6) + $f.Extension.ToLower())
        Move-Item -LiteralPath $f.FullName -Destination $dest -Force
        Write-Host ("{0}  ->  Duplicati (foto identica già ricevuta, ignorata)" -f $f.Name); continue
      }
      $r = Parse-Receipt (Read-Text $f.FullName)
      $r.files = @($f.FullName); $r.orig = $f.BaseName; $r.id = [guid]::NewGuid().ToString('N').Substring(0,8)

      $target = $null; $before = 0; $msg = 'nuovo scontrino'
      foreach ($e in @($script:state.receipts)) {
        $m = Try-Merge $e $r
        if ($null -ne $m) { $target = $e; $before = @($e.lines).Count; Absorb $e $r $m; break }
      }
      if ($target) {
        # la nuova foto può collegare due scontrini rimasti incompleti: unisco anche quelli
        do {
          $again = $false
          foreach ($o in @($script:state.receipts)) {
            if ($o.id -eq $target.id) { continue }
            $m = Try-Merge $target $o
            if ($null -ne $m) {
              Absorb $target $o $m
              if ($o.txt -and (Test-Path -LiteralPath $o.txt)) { Remove-Item -LiteralPath $o.txt -Force }
              $script:state.receipts = [object[]]@($script:state.receipts | Where-Object { $_.id -ne $o.id })
              $again = $true; break
            }
          }
        } while ($again)
        $added = @($target.lines).Count - $before
        $msg = if ($added -gt 0) { "unita a uno scontrino già presente: +$added righe nuove" } else { "unita a uno scontrino già presente: nessuna riga nuova (era già coperta)" }
      } else {
        $script:state.receipts = [object[]](@($script:state.receipts) + $r); $target = $r
      }
      Place-Receipt $target
      $script:state.hashes = [object[]](@($script:state.hashes) + $hash)
      Save-State
      Write-Host ("{0}  ->  {1}  [{2}; {3}]" -f $f.Name, (Split-Path $target.files[-1] -Leaf), $msg, (Check-Total $target))
    } catch {
      Write-Warning "Errore su $($f.Name): $($_.Exception.Message)"
    }
  }
}

Process-All
if ($Watch) {
  Write-Host "In ascolto su $new (Ctrl+C per uscire)..."
  while ($true) { Start-Sleep -Seconds 5; Process-All }
}
