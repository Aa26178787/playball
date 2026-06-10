# Build HTML to collect handles for MISSING players (google/namu links + input -> Generate id|name|handle)
# Input : insta_missing_html.tsv (id<TAB>team<TAB>name<TAB>is_foreign)
# Output: insta_missing.html
$rows = Import-Csv "$PSScriptRoot\insta_missing_html.tsv" -Delimiter "`t" -Header id,team,name,foreign -Encoding UTF8

$head = @'
<!doctype html><html><head><meta charset="utf-8"><title>missing insta</title>
<style>
body{font-family:-apple-system,Segoe UI,sans-serif;margin:0;background:#0d0d10;color:#eee}
#bar{position:sticky;top:0;background:#16161b;padding:10px 14px;border-bottom:1px solid #333;z-index:9;font-size:14px}
#bar b{color:#7ab8ff}
.team{font-weight:700;color:#7ab8ff;margin:16px 14px 4px;font-size:15px}
.r{display:flex;align-items:center;gap:9px;padding:6px 14px;border-bottom:1px solid #1d1d22}
.r .nm{flex:0 0 130px;font-size:14px;font-weight:600}
.r .nm .fg{color:#e88;font-size:11px}
.r a{font-size:12px;text-decoration:none}.r a.g{color:#9ad}.r a.n{color:#9d9}
.r input.h{flex:1;max-width:220px;background:#1d1d22;border:1px solid #333;color:#eee;padding:6px;border-radius:5px;font-size:13px}
.r label{font-size:12px;color:#aaa;white-space:nowrap}
#gen{position:fixed;right:16px;bottom:16px;background:#2a6;color:#fff;border:0;padding:12px 18px;border-radius:24px;font-size:15px;cursor:pointer;z-index:20}
#out{position:fixed;left:0;right:0;bottom:0;height:0;background:#000;color:#0f0;font-family:monospace;font-size:12px;overflow:auto;white-space:pre;transition:height .2s}
#out.show{height:45vh;padding:12px}
</style></head><body>
<div id="bar"><b>missing insta</b> &middot; 핬들 입력 후 Generate &rarr; <b>id|이름|핸들</b> 복사해서 보내주면 imginn 검증후 적용 &middot; <span id=cnt>0</span></div>
'@

$sb = New-Object System.Text.StringBuilder
[void]$sb.Append($head)
$lastTeam = ''
foreach ($r in $rows) {
  if ($r.team -ne $lastTeam) { [void]$sb.Append("<div class='team'>$($r.team)</div>"); $lastTeam = $r.team }
  $fg = if ($r.foreign -eq 'true') { " <span class='fg'>(외)</span>" } else { '' }
  $g = "https://www.google.com/search?q=$([uri]::EscapeDataString($r.name + ' 야구 인스타그램'))"
  $n = "https://namu.wiki/w/$([uri]::EscapeDataString($r.name))"
  [void]$sb.Append("<div class='r' data-id='$($r.id)' data-name='$($r.name)'><span class='nm'>$($r.name)$fg</span><a class='g' href='$g' target='_blank'>google</a> <a class='n' href='$n' target='_blank'>namu</a><input class='h' placeholder='handle (@ 제외)'></div>")
}
$foot = @'
<button id="gen" onclick="gen()">Generate</button><div id="out"></div>
<script>
document.addEventListener("input",function(){var c=0;document.querySelectorAll(".h").forEach(function(i){if(i.value.trim())c++});document.getElementById("cnt").textContent=c});
function gen(){var s=[];document.querySelectorAll(".r").forEach(function(r){var h=r.querySelector(".h").value.trim().replace(/^@/,"");if(h)s.push(r.dataset.id+"|"+r.dataset.name+"|"+h)});var o=document.getElementById("out");o.textContent=s.length?s.join("\n"):"(none)";o.classList.add("show");o.scrollIntoView()}
</script></body></html>
'@
[void]$sb.Append($foot)
[IO.File]::WriteAllText("$PSScriptRoot\insta_missing.html", $sb.ToString(), (New-Object Text.UTF8Encoding $true))
Write-Output "wrote insta_missing.html ($($rows.Count) players)"
