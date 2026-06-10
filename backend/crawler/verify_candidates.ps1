# Verify naver candidate handles for missing players via imginn -> picnob (display-name ownership check)
# Input : insta_naver_cands.tsv (id<TAB>team<TAB>name<TAB>handle<TAB>rank)
# Output: insta_fill_verified.csv — first VERIFIED candidate per player wins; all attempts logged
$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [Text.Encoding]::UTF8
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$UA = @{'User-Agent'='Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0 Safari/537.36'}
$TKW = @{
  'HH'='한화|hanwha'; 'HT'='KIA|타이거즈|tigers|kia'; 'KT'='위즈|wiz|ktwiz'; 'LG'='트윈스|twins|lgtwins';
  'LT'='롯데|자이언츠|giants|lotte'; 'NC'='다이노스|dinos|ncdinos'; 'OB'='두산|베어스|bears|doosan';
  'SK'='SSG|랜더스|landers'; 'SS'='삼성|라이온즈|lions|samsung'; 'WO'='키움|히어로즈|heroes|kiwoom'
}

function Get-Viewer($url) {
  $r = @{code=0; disp=''; bio=''}
  try {
    $resp = Invoke-WebRequest -UseBasicParsing -Uri $url -Headers $UA -TimeoutSec 20
    $r.code = 200
    if ($resp.Content -match 'og:title" content="([^"]+)"') { $r.disp = ($Matches[1] -replace '\(@.*$', '').Trim() }
    if ($resp.Content -match 'og:description" content="([^"]+)"') { $r.bio = $Matches[1] }
  } catch { try { $r.code = [int]$_.Exception.Response.StatusCode.value__ } catch { $r.code = 0 } }
  return $r
}
function Get-ViewerCurl($url) {
  $r = @{code=0; disp=''; bio=''}
  $tmp = Join-Path $env:TEMP 'picnob_cand.html'
  $code = & curl.exe -s -A 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0 Safari/537.36' --max-time 20 -o $tmp -w '%{http_code}' $url
  try { $r.code = [int]$code } catch { $r.code = 0 }
  if ($r.code -eq 200 -and (Test-Path $tmp)) {
    $html = [IO.File]::ReadAllText($tmp, [Text.Encoding]::UTF8)
    if ($html -match 'og:title" content="([^"]+)"') { $r.disp = ($Matches[1] -replace '\(@.*$', '').Trim() }
    if ($html -match 'og:description" content="([^"]+)"') { $r.bio = $Matches[1] }
  }
  return $r
}
function Get-Verdict($name, $team, $disp, $bio) {
  if (-not $disp) { return '' }
  # NFKC: fancy unicode (bold/italic letters) -> plain ASCII/Hangul
  $dn = ($disp.Normalize([Text.NormalizationForm]::FormKC) -replace '\s','')
  $nn = ($name.Normalize([Text.NormalizationForm]::FormC) -replace '\s','')
  $bn = ''
  if ($bio) { $bn = ($bio.Normalize([Text.NormalizationForm]::FormKC) -replace '\s','') }
  if ($nn -and $dn -and ($dn.Contains($nn) -or $nn.Contains($dn))) { return 'VERIFIED_NAME' }
  if ($nn -and $bn -and $bn.Contains($nn)) { return 'VERIFIED_NAME_BIO' }
  $kw = $TKW[$team]
  if ($kw -and ($bio -match $kw -or $disp -match $kw)) { return 'VERIFIED_TEAM' }
  return 'NAME_MISMATCH'
}

$rows = Import-Csv "$PSScriptRoot\insta_naver_cands.tsv" -Delimiter "`t" -Header id,team,name,handle,rank -Encoding UTF8
$byPlayer = $rows | Group-Object id
Write-Output "players with candidates: $($byPlayer.Count)"
$out = New-Object System.Collections.Generic.List[object]
$i = 0
foreach ($g in $byPlayer) {
  $i++
  $found = $false
  foreach ($r in ($g.Group | Sort-Object {[int]$_.rank})) {
    if ($found) { break }
    $h = $r.handle.Trim()
    $verdict = 'unknown'; $src = ''; $disp = ''; $bio = ''
    $im = Get-Viewer "https://imginn.com/$h/"
    if ($im.code -eq 429 -or $im.code -eq 0) { Start-Sleep -Seconds 6; $im = Get-Viewer "https://imginn.com/$h/" }
    if ($im.disp) { $verdict = Get-Verdict $r.name $r.team $im.disp $im.bio; $src='imginn'; $disp=$im.disp; $bio=$im.bio }
    else {
      Start-Sleep -Milliseconds 1500
      $pn = Get-ViewerCurl "https://www.picnob.com/profile/$h/"
      if ($pn.disp) { $verdict = Get-Verdict $r.name $r.team $pn.disp $pn.bio; $src='picnob'; $disp=$pn.disp; $bio=$pn.bio }
      elseif ($im.code -eq 410 -or $pn.code -in 404,410) { $verdict = 'GONE_OR_PRIVATE' }
    }
    $out.Add([pscustomobject]@{ id=$r.id; team=$r.team; name=$r.name; handle=$h; rank=$r.rank; verdict=$verdict; src=$src; disp=$disp; bio=($bio.Substring(0,[Math]::Min(80,$bio.Length))) })
    Write-Output "[$i/$($byPlayer.Count)] $($r.team) $($r.name) @$h -> $verdict($src) disp=$disp"
    if ($verdict -like 'VERIFIED*') { $found = $true }
    Start-Sleep -Milliseconds 2500
  }
}
$out | Export-Csv -Path "$PSScriptRoot\insta_fill_verified.csv" -NoTypeInformation -Encoding UTF8
$v = @($out | Where-Object { $_.verdict -like 'VERIFIED*' })
Write-Output "DONE -> insta_fill_verified.csv  verified players=$(@($v | Select-Object -Unique id).Count)"
