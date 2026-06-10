# Re-verify ALL registered insta handles via TWO independent viewers: imginn.com -> picnob.com fallback
# Input : insta_registered.tsv  (id<TAB>team<TAB>name<TAB>handle — fresh DB export, all non-empty)
# Output: insta_dual.csv  (verdict: VERIFIED_NAME / VERIFIED_TEAM / NAME_MISMATCH / GONE_OR_PRIVATE / unknown)
# Usage : powershell -File verify_dual_all.ps1 [-Limit N]
param([int]$Limit = 0, [string]$InFile = 'insta_registered.tsv', [string]$OutFile = 'insta_dual.csv')
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
  # returns @{code=..; disp=..; bio=..} ; code 0 = network fail
  $r = @{code=0; disp=''; bio=''}
  try {
    $resp = Invoke-WebRequest -UseBasicParsing -Uri $url -Headers $UA -TimeoutSec 20
    $r.code = 200
    if ($resp.Content -match 'og:title" content="([^"]+)"') {
      $r.disp = ($Matches[1] -replace '\(@.*$', '').Trim()
    }
    if ($resp.Content -match 'og:description" content="([^"]+)"') { $r.bio = $Matches[1] }
  } catch {
    try { $r.code = [int]$_.Exception.Response.StatusCode.value__ } catch { $r.code = 0 }
  }
  return $r
}

function Get-ViewerCurl($url) {
  # picnob blocks PS5.1 Invoke-WebRequest (TLS fingerprint 403) -> use curl.exe, UTF-8 via temp file
  $r = @{code=0; disp=''; bio=''}
  $tmp = Join-Path $env:TEMP 'picnob_dual.html'
  $code = & curl.exe -s -A 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0 Safari/537.36' --max-time 20 -o $tmp -w '%{http_code}' $url
  try { $r.code = [int]$code } catch { $r.code = 0 }
  if ($r.code -eq 200 -and (Test-Path $tmp)) {
    $html = [IO.File]::ReadAllText($tmp, [Text.Encoding]::UTF8)
    if ($html -match 'og:title" content="([^"]+)"') {
      $r.disp = ($Matches[1] -replace '\(@.*$', '').Trim()
    }
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

$rows = Import-Csv "$PSScriptRoot\$InFile" -Delimiter "`t" -Header id,team,name,handle -Encoding UTF8 |
        Where-Object { $_.handle -and $_.handle.Trim() }
if ($Limit -gt 0) { $rows = $rows | Select-Object -First $Limit }
Write-Output "handles to verify: $($rows.Count)"
$out = New-Object System.Collections.Generic.List[object]
$i = 0
foreach ($r in $rows) {
  $i++
  $h = $r.handle.Trim()
  $verdict = 'unknown'; $src = ''; $disp = ''; $bio = ''
  # 1) imginn (retry once on 429/timeout)
  $im = Get-Viewer "https://imginn.com/$h/"
  if ($im.code -eq 429 -or $im.code -eq 0) { Start-Sleep -Seconds 6; $im = Get-Viewer "https://imginn.com/$h/" }
  if ($im.disp) {
    $verdict = Get-Verdict $r.name $r.team $im.disp $im.bio
    $src = 'imginn'; $disp = $im.disp; $bio = $im.bio
  }
  # 2) picnob fallback when imginn gave no profile data (410 private/deleted, 429, etc.)
  $pn = @{code=''}
  if (-not $im.disp) {
    Start-Sleep -Milliseconds 1500
    $pn = Get-ViewerCurl "https://www.picnob.com/profile/$h/"
    if ($pn.disp) {
      $verdict = Get-Verdict $r.name $r.team $pn.disp $pn.bio
      $src = 'picnob'; $disp = $pn.disp; $bio = $pn.bio
    } elseif ($im.code -eq 410 -or $pn.code -eq 404 -or $pn.code -eq 410) {
      $verdict = 'GONE_OR_PRIVATE'
    }
  }
  $out.Add([pscustomobject]@{
    id=$r.id; team=$r.team; name=$r.name; handle=$h; verdict=$verdict; src=$src
    imginn_code=$im.code; picnob_code=$pn.code; disp=$disp
    bio=($bio.Substring(0,[Math]::Min(80,$bio.Length)))
  })
  $tag = "[$i/$($rows.Count)] $verdict($src) $($r.team) $($r.name) @$h"
  if ($verdict -in 'NAME_MISMATCH','GONE_OR_PRIVATE','unknown') { $tag += " im=$($im.code) pn=$($pn.code) disp=$disp" }
  Write-Output $tag
  Start-Sleep -Milliseconds 2500
}
$out | Export-Csv -Path "$PSScriptRoot\$OutFile" -NoTypeInformation -Encoding UTF8
foreach ($v in 'VERIFIED_NAME','VERIFIED_NAME_BIO','VERIFIED_TEAM','NAME_MISMATCH','GONE_OR_PRIVATE','unknown') {
  $n = @($out | Where-Object { $_.verdict -eq $v }).Count
  Write-Output "$v = $n"
}
Write-Output "DONE -> $OutFile"
