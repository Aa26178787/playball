import requests
import json

headers = {
    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36",
    "Referer": "https://sports.naver.com/"
}

url = "https://api-gw.sports.naver.com/statistics/categories/kbo/seasons/2026/players?sortField=hitterHra&sortDirection=desc&playerType=HITTER&pageSize=5"

res = requests.get(url, headers=headers, timeout=10)
data = res.json()

for p in data["result"]["seasonPlayerStats"][:3]:
    player_id = p.get("playerId")
    name = p.get("playerName")
    print(f"{name}: playerId={player_id}")
    
    # KBO 사이트에서 같은 ID로 조회되는지 확인
    from bs4 import BeautifulSoup
    kbo_url = f"https://www.koreabaseball.com/Record/Player/HitterDetail/Basic.aspx?playerId={player_id}"
    kbo_res = requests.get(kbo_url, headers={"User-Agent": "Mozilla/5.0"}, timeout=10)
    kbo_soup = BeautifulSoup(kbo_res.text, "html.parser")
    kbo_text = kbo_soup.get_text()
    kbo_lines = [l.strip() for l in kbo_text.split('\n') if l.strip()]
    for line in kbo_lines:
        if '생년월일' in line:
            print(f"  → {line}")
            break