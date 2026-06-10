# Verify DB insta handles by IG profile DISPLAY NAME via imginn.com (3rd-party viewer, no login)
# Input : insta_review.tsv  (id<TAB>team<TAB>name<TAB>handle<TAB>photo<TAB>rep)
# Output: insta_imginn.csv  (verdict: VERIFIED_NAME / VERIFIED_TEAM / NAME_MISMATCH / unknown)
# imginn og:title = "<displayname>(@handle) ...". match displayname vs player name => ownership.
$ErrorActionPreference = 'Continue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$UA = @{'User-Agent'='Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36'}
# team_code -> bio keyword (Korean team name or official handle fragment) for English-name players
$TKW = @{
  'HH'='한화|hanwha'; 'HT'='KIA|타이거즈|tigers|kia'; 'KT'='위즈|wiz|ktwiz'; 'LG'='트윈스|twins|lgtwins';
  'LT'='롯데|자이언츠|giants|lotte'; 'NC'='다이노스|dinos|ncdinos'; 'OB'='두산|베어스|bears|doosan';
  'SK'='SSG|랜더스|landers'; 'SS'='삼성|라이온즈|lions|samsung'; 'WO'='키움|히어로즈|heroes|kiwoom'
}

$rows = Import-Csv "$PSScriptRoot\insta_review.tsv" -Delimiter "`t" -Header id,team,name,handle,photo,rep -Encoding UTF8
Write-Output "players: $($rows.Count)"
$out = New-Object System.Collections.Generic.List[object]
$i = 0
foreach ($r in $rows) {
  $i++
  $disp = ''; $bio = ''; $verdict = 'unknown'
  try {
    $resp = Invoke-WebRequest -UseBasicParsing -Uri "https://imginn.com/$($r.handle)/" -Headers $UA -TimeoutSec 15
    if ($resp.Content -match 'og:title" content="([^"]+)"') {
      $disp = ($Matches[1] -replace '\(@.*$', '').Trim()
    }
    if ($resp.Content -match 'og:description" content="([^"]+)"') { $bio = $Matches[1] }
    if ($disp) {
      $kw = $TKW[$r.team]
      # NFC 정규화 + 공백제거 후 포함 비교 (imginn 한글 NFD vs DB NFC 불일치 방지)
      $dn = ($disp.Normalize([Text.NormalizationForm]::FormC) -replace '\s','')
      $nn = ($r.name.Normalize([Text.NormalizationForm]::FormC) -replace '\s','')
      if ($nn -and $dn -and ($dn.Contains($nn) -or $nn.Contains($dn))) { $verdict = 'VERIFIED_NAME' }
      elseif ($kw -and ($bio -match $kw -or $disp -match $kw)) { $verdict = 'VERIFIED_TEAM' }
      else { $verdict = 'NAME_MISMATCH' }
    }
  } catch { $verdict = 'unknown' }
  $out.Add([pscustomobject]@{ id=$r.id; team=$r.team; name=$r.name; handle=$r.handle; verdict=$verdict; disp=$disp; bio=($bio.Substring(0,[Math]::Min(60,$bio.Length))) })
  if ($verdict -eq 'NAME_MISMATCH') { Write-Output "[$i/$($rows.Count)] *** MISMATCH $($r.team) $($r.name) @$($r.handle) disp=$disp" }
  else { Write-Output "[$i/$($rows.Count)] $verdict $($r.team) $($r.name)" }
  Start-Sleep -Milliseconds 1600
}
$out | Export-Csv -Path "$PSScriptRoot\insta_imginn.csv" -NoTypeInformation -Encoding UTF8
$mm = @($out | Where-Object { $_.verdict -eq 'NAME_MISMATCH' })
$uk = @($out | Where-Object { $_.verdict -eq 'unknown' })
Write-Output "DONE -> insta_imginn.csv  MISMATCH=$($mm.Count) unknown=$($uk.Count)"
