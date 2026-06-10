# Verify imginn-unknown handles via Naver search (best KR coverage). Free direct fetch.
# Input : insta_imginn.csv (uses verdict=unknown rows)
# Output: insta_naver.csv  (verdict: VERIFIED_NAVER / not_in_naver / no_result)
# Naver search "<name> 인스타그램" HTML => instagram links. DB handle present => confirmed.
$ErrorActionPreference = 'Continue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$UA = @{'User-Agent'='Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36'}

$all = Import-Csv "$PSScriptRoot\insta_imginn.csv" -Encoding UTF8
$rows = $all | Where-Object { $_.verdict -eq 'unknown' }
Write-Output "unknown to recheck: $($rows.Count)"
$out = New-Object System.Collections.Generic.List[object]
$i = 0
foreach ($r in $rows) {
  $i++
  $verdict = 'no_result'; $found = ''
  try {
    $q = [uri]::EscapeDataString($r.name + ' 인스타그램')
    $resp = Invoke-WebRequest -UseBasicParsing -Uri "https://search.naver.com/search.naver?query=$q" -Headers $UA -TimeoutSec 15
    $hs = [regex]::Matches($resp.Content, 'instagram\.com/([A-Za-z0-9._]{2,30})') | ForEach-Object { $_.Groups[1].Value.TrimEnd('.') } | Select-Object -Unique
    $found = ($hs -join ',')
    if ($hs.Count) {
      if ($hs -contains $r.handle) { $verdict = 'VERIFIED_NAVER' }
      else { $verdict = 'not_in_naver' }
    }
  } catch {}
  $out.Add([pscustomobject]@{ id=$r.id; team=$r.team; name=$r.name; handle=$r.handle; verdict=$verdict; naver_found=$found })
  if ($verdict -eq 'not_in_naver') { Write-Output "[$i/$($rows.Count)] ?? not_in_naver $($r.team) $($r.name) db=$($r.handle) naver=$found" }
  else { Write-Output "[$i/$($rows.Count)] $verdict $($r.team) $($r.name)" }
  Start-Sleep -Milliseconds 1400
}
$out | Export-Csv -Path "$PSScriptRoot\insta_naver.csv" -NoTypeInformation -Encoding UTF8
$v = @($out | Where-Object { $_.verdict -eq 'VERIFIED_NAVER' })
$n = @($out | Where-Object { $_.verdict -eq 'not_in_naver' })
Write-Output "DONE -> insta_naver.csv  VERIFIED=$($v.Count) not_in_naver=$($n.Count) no_result=$($out.Count - $v.Count - $n.Count)"
