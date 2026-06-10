# Collect instagram handle CANDIDATES for missing players via Naver web search (no verification here)
# Input : insta_missing_fresh.tsv (id<TAB>team<TAB>name<TAB>position<TAB>type)
# Output: insta_naver_cands.tsv  (id<TAB>team<TAB>name<TAB>handle<TAB>rank) — verify later via imginn/picnob
$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$TNAME = @{
  'HH'='한화'; 'HT'='KIA'; 'KT'='KT'; 'LG'='LG'; 'LT'='롯데';
  'NC'='NC'; 'OB'='두산'; 'SK'='SSG'; 'SS'='삼성'; 'WO'='키움'
}
# noise handles to ignore (team/league/media official accounts)
$NOISE = '^(kbo|kbo_official|hanwhaeagles|kiatigers|ktwiz|lgtwins|lottegiants|ncdinos|doosanbears|ssglanders|samsunglions|kiwoomheroes|naver|instagram)'

$rows = Import-Csv "$PSScriptRoot\insta_missing_fresh.tsv" -Delimiter "`t" -Header id,team,name,position,type -Encoding UTF8
Write-Output "players: $($rows.Count)"
$out = New-Object System.Collections.Generic.List[string]
$tmp = Join-Path $env:TEMP 'naver_cand.html'
$i = 0
foreach ($r in $rows) {
  $i++
  $q = [Uri]::EscapeDataString("$($TNAME[$r.team]) $($r.name) 인스타그램")
  $code = & curl.exe -s -A 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0 Safari/537.36' --max-time 20 -o $tmp -w '%{http_code}' "https://search.naver.com/search.naver?query=$q"
  $cands = @()
  if ($code -eq '200' -and (Test-Path $tmp)) {
    $html = [IO.File]::ReadAllText($tmp, [Text.Encoding]::UTF8)
    $m = [regex]::Matches($html, 'instagram\.com/([A-Za-z0-9_][A-Za-z0-9_.]{1,29})')
    $seen = New-Object System.Collections.Generic.HashSet[string]
    foreach ($mm in $m) {
      $h = $mm.Groups[1].Value.TrimEnd('.')
      if ($h -in 'p','reel','reels','explore','stories','tv','accounts','share') { continue }
      if ($h -match $NOISE) { continue }
      if ($seen.Add($h.ToLower())) { $cands += $h }
      if ($cands.Count -ge 5) { break }
    }
  }
  $rank = 0
  foreach ($c in $cands) {
    $rank++
    $out.Add("$($r.id)`t$($r.team)`t$($r.name)`t$c`t$rank")
  }
  Write-Output "[$i/$($rows.Count)] $($r.team) $($r.name) http=$code cands=$($cands -join ',')"
  Start-Sleep -Milliseconds 2500
}
[IO.File]::WriteAllLines("$PSScriptRoot\insta_naver_cands.tsv", $out, (New-Object Text.UTF8Encoding $false))
Write-Output "DONE -> insta_naver_cands.tsv ($($out.Count) candidate rows)"
