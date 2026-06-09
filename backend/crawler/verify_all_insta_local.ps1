# Verify ALL current DB insta handles against live namu.wiki (run from LOCAL PC - server IP gets 403)
# Input : insta_current.tsv  (id<TAB>team_code<TAB>name<TAB>db_handle)   exported from DB
# Output: insta_verify_report.csv  (verdict: ok / MISMATCH / FILL / namu_none / still_missing)
# NOTE: ASCII-only console messages (PS5.1 reads no-BOM UTF8 as ANSI)
$ErrorActionPreference = 'Continue'
$UAHDR = @{'User-Agent'='Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36'}

# team_code -> namu disambiguation keyword (page must contain this to trust the instagram link)
$TEAMKW = @{
  'HH'='한화'; 'HT'='KIA'; 'KT'='위즈'; 'LG'='트윈스'; 'LT'='롯데 자이언츠';
  'NC'='다이노스'; 'OB'='두산'; 'SK'='SSG'; 'SS'='삼성 라이온즈'; 'WO'='키움'
}
$reserved = @('p','reel','reels','explore','accounts','stories','tv','about','directory')
$ygkw = [char]0xC57C + [char]0xAD6C            # 'yagu' (baseball) guard
$suffix = '(' + $ygkw + [char]0xC120 + [char]0xC218 + ')'  # (yagu-seonsu)

$rows = Import-Csv "$PSScriptRoot\insta_current.tsv" -Delimiter "`t" -Header id,team,name,db -Encoding UTF8
Write-Output "players: $($rows.Count)"

$out = New-Object System.Collections.Generic.List[object]
$i = 0
foreach ($r in $rows) {
  $i++
  $kw = $TEAMKW[$r.team]
  $namu = ''
  foreach ($title in @(($r.name + $suffix), $r.name)) {   # disambig page first
    try {
      $enc = [uri]::EscapeDataString($title)
      $resp = Invoke-WebRequest -UseBasicParsing -Uri "https://namu.wiki/w/$enc" -Headers $UAHDR -TimeoutSec 12
      if ($resp.StatusCode -eq 200) {
        $teamOk = (-not $kw) -or ($resp.Content -match [regex]::Escape($kw))
        $isYg   = $resp.Content -match $ygkw
        if ($teamOk -and $isYg) {
          $ms = [regex]::Matches($resp.Content, 'instagram\.com/([A-Za-z0-9._]{2,30})')
          foreach ($m in $ms) {
            $h = $m.Groups[1].Value.TrimEnd('.')
            if ($reserved -notcontains $h.ToLower()) { $namu = $h; break }
          }
        }
        if ($namu) { break }
      }
    } catch {}
    Start-Sleep -Milliseconds 1500
  }

  $db = $r.db
  if ($namu) {
    if (-not $db)                          { $verdict = 'FILL' }
    elseif ($db.ToLower() -eq $namu.ToLower()) { $verdict = 'ok' }
    else                                   { $verdict = 'MISMATCH' }
  } else {
    if ($db) { $verdict = 'namu_none' } else { $verdict = 'still_missing' }
  }
  $out.Add([pscustomobject]@{ id=$r.id; team=$r.team; name=$r.name; db_handle=$db; namu_handle=$namu; verdict=$verdict })

  if ($verdict -eq 'MISMATCH' -or $verdict -eq 'FILL') {
    Write-Output "[$i/$($rows.Count)] *** $verdict  $($r.team) $($r.name)  db=$db namu=$namu"
  } else {
    Write-Output "[$i/$($rows.Count)] $verdict  $($r.team) $($r.name)"
  }
  Start-Sleep -Milliseconds 1500
}

$out | Export-Csv -Path "$PSScriptRoot\insta_verify_report.csv" -NoTypeInformation -Encoding UTF8
$mm = @($out | Where-Object { $_.verdict -eq 'MISMATCH' })
$fl = @($out | Where-Object { $_.verdict -eq 'FILL' })
Write-Output "DONE -> insta_verify_report.csv  MISMATCH=$($mm.Count) FILL=$($fl.Count)"
