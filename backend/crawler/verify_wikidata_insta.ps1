# Cross-check DB insta handles against Wikidata P2003 (Instagram username) - high precision
# Input : insta_current.tsv  (id<TAB>team<TAB>name<TAB>db_handle)
# Output: insta_wikidata.csv  (verdict: ok / MISMATCH / FILL_wd / wd_none / no_entity)
# Wikidata API = no blocking, ToS-friendly. ASCII-only console.
$ErrorActionPreference = 'Continue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12  # PS5.1 default omits TLS1.2 -> wikidata HTTPS fails in bg
$UA = @{'User-Agent'='playball-kbo-insta-verify/1.0 (https://playball.duckdns.org)'}  # wikidata API requires descriptive UA, else throttled

$rows = Import-Csv "$PSScriptRoot\insta_current.tsv" -Delimiter "`t" -Header id,team,name,db -Encoding UTF8
Write-Output "players: $($rows.Count)"
$out = New-Object System.Collections.Generic.List[object]
$i = 0
foreach ($r in $rows) {
  $i++
  $wd = ''; $qid = ''
  try {
    $enc = [uri]::EscapeDataString($r.name)
    $s = Invoke-RestMethod -TimeoutSec 12 -Headers $UA -Uri "https://www.wikidata.org/w/api.php?action=wbsearchentities&search=$enc&language=en&uselang=en&type=item&limit=8&format=json"
    foreach ($h in $s.search) {
      if ("$($h.description)" -match 'baseball') { $qid = $h.id; break }
    }
    if ($qid) {
      $c = Invoke-RestMethod -TimeoutSec 12 -Headers $UA -Uri "https://www.wikidata.org/w/api.php?action=wbgetclaims&entity=$qid&property=P2003&format=json"
      if ($c.claims.P2003) { $wd = "$($c.claims.P2003[0].mainsnak.datavalue.value)" }
    }
  } catch {}

  $db = $r.db
  if (-not $qid)                              { $verdict = 'no_entity' }
  elseif (-not $wd)                           { $verdict = 'wd_none' }
  elseif (-not $db)                           { $verdict = 'FILL_wd' }
  elseif ($db.ToLower() -eq $wd.ToLower())    { $verdict = 'ok' }
  else                                        { $verdict = 'MISMATCH' }
  $out.Add([pscustomobject]@{ id=$r.id; team=$r.team; name=$r.name; db_handle=$db; wd_handle=$wd; qid=$qid; verdict=$verdict })

  if ($verdict -eq 'MISMATCH' -or $verdict -eq 'FILL_wd') {
    Write-Output "[$i/$($rows.Count)] *** $verdict  $($r.team)  db=$db wd=$wd"
  } else {
    Write-Output "[$i/$($rows.Count)] $verdict  $($r.team)"
  }
  Start-Sleep -Milliseconds 500
}
$out | Export-Csv -Path "$PSScriptRoot\insta_wikidata.csv" -NoTypeInformation -Encoding UTF8
$mm = @($out | Where-Object { $_.verdict -eq 'MISMATCH' })
$fl = @($out | Where-Object { $_.verdict -eq 'FILL_wd' })
Write-Output "DONE -> insta_wikidata.csv  MISMATCH=$($mm.Count) FILL_wd=$($fl.Count)"
