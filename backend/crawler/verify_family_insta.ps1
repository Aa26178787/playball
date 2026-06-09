# Audit DB insta handles for FAMILY-account errors (namu grabbed a relative's IG, not the player's)
# Input : insta_haveh.tsv  (id<TAB>team<TAB>name<TAB>db_handle)
# Output: insta_family_audit.csv  (verdict: FAMILY_SUSPECT / ok_self / not_on_namu)
# Run from LOCAL PC (namu blocks server IP). ASCII-only console.
$ErrorActionPreference = 'Continue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$UA = @{'User-Agent'='Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36'}
$ygkw = [char]0xC57C + [char]0xAD6C
$sfx  = '(' + $ygkw + [char]0xC120 + [char]0xC218 + ')'   # (yagu-seonsu)
# 가족 마커 (핸들 앞 텍스트에 있으면 본인 아닌 가족 계정 의심)
$fam = '아내|배우자|어머니|아버지|모친|부친|자녀|아들|딸|여동생|남동생|누나|형|가족|와이프|부모|장인|장모'

$rows = Import-Csv "$PSScriptRoot\insta_haveh.tsv" -Delimiter "`t" -Header id,team,name,db -Encoding UTF8
Write-Output "players: $($rows.Count)"
$out = New-Object System.Collections.Generic.List[object]
$i = 0
foreach ($r in $rows) {
  $i++
  $verdict = 'not_on_namu'; $allh = ''
  foreach ($title in @(($r.name + $sfx), $r.name)) {
    try {
      $enc = [uri]::EscapeDataString($title)
      $resp = Invoke-WebRequest -UseBasicParsing -Uri "https://namu.wiki/w/$enc" -Headers $UA -TimeoutSec 12
      if ($resp.StatusCode -ne 200) { continue }
      $c = $resp.Content
      $idx = $c.IndexOf("instagram.com/$($r.db)")
      if ($idx -lt 0) { continue }   # this title page doesn't have the handle, try next
      $allh = (([regex]::Matches($c,'instagram\.com/([A-Za-z0-9._]{2,30})') | ForEach-Object { $_.Groups[1].Value.TrimEnd('.') } | Select-Object -Unique) -join ',')
      $start = [Math]::Max(0, $idx - 320)
      $pre = ($c.Substring($start, $idx - $start) -replace '<[^>]+>', ' ')
      if ($pre -match $fam) { $verdict = 'FAMILY_SUSPECT' } else { $verdict = 'ok_self' }
      break
    } catch {}
    Start-Sleep -Milliseconds 1200
  }
  $out.Add([pscustomobject]@{ id=$r.id; team=$r.team; name=$r.name; db_handle=$r.db; verdict=$verdict; namu_all=$allh })
  if ($verdict -eq 'FAMILY_SUSPECT') { Write-Output "[$i/$($rows.Count)] *** FAMILY  $($r.team) $($r.name)  db=$($r.db)  page=$allh" }
  else { Write-Output "[$i/$($rows.Count)] $verdict  $($r.team) $($r.name)" }
  Start-Sleep -Milliseconds 1300
}
$out | Export-Csv -Path "$PSScriptRoot\insta_family_audit.csv" -NoTypeInformation -Encoding UTF8
$f = @($out | Where-Object { $_.verdict -eq 'FAMILY_SUSPECT' })
Write-Output "DONE -> insta_family_audit.csv  FAMILY_SUSPECT=$($f.Count)"
