# test_keywords.py
from selenium import webdriver
from selenium.webdriver.chrome.options import Options
from selenium.webdriver.common.by import By
from selenium.webdriver.support.ui import WebDriverWait
from selenium.webdriver.support import expected_conditions as EC
import time, re

options = Options()
driver = webdriver.Chrome(options=options)

game_ids = [
    '20260507HHHT02026',
    '20260505NCSK02026',
    '20260503SSLG02026',
    '20260501HHHT02026',
]

inning_pattern = re.compile(r'^(\d+)회(초|말)\s+\S+\s+공격$')
pitch_info_pattern = re.compile(r'^(\d+)km/h(.+)$')
batter_pattern = re.compile(r'^(.+?)(\d+)번타자타율\s+([\d.]+)$')

# 무시할 패턴
ignore_patterns = [
    re.compile(r'선수 페이지$'),
    re.compile(r'^타석\d+$'),
    re.compile(r'^타수\d+$'),
    re.compile(r'^안타\d+$'),
    re.compile(r'^득점\d+$'),
    re.compile(r'^타점\d+$'),
    re.compile(r'^홈런\d+$'),
    re.compile(r'^볼넷\d+$'),
    re.compile(r'^피삼진\d+$'),
    re.compile(r'^기록 펼치기$'),
    re.compile(r'^투구 위치보기$'),
    re.compile(r'^볼카운트$'),
    re.compile(r'^\d+ - \d+$'),
    re.compile(r'^구$'),
    re.compile(r'^\d+$'),
]

def should_ignore(line):
    for p in ignore_patterns:
        if p.match(line):
            return True
    if pitch_info_pattern.match(line):
        return True
    if batter_pattern.match(line):
        return True
    return False

all_lines = set()

for game_id in game_ids:
    print(f'수집 중: {game_id}')
    driver.get(f'https://m.sports.naver.com/game/{game_id}/relay')
    WebDriverWait(driver, 15).until(EC.presence_of_element_located((By.TAG_NAME, 'body')))
    time.sleep(4)

    inning_buttons = driver.find_elements(By.CLASS_NAME, 'SetTab_button_tab__XW5t5')
    for btn in inning_buttons:
        try:
            driver.execute_script("arguments[0].click();", btn)
            time.sleep(1.2)
            text = driver.execute_script("return document.body.innerText")
            lines = [l.strip() for l in text.split('\n') if l.strip()]

            in_relay = False
            for line in lines:
                if inning_pattern.match(line):
                    in_relay = True
                if not in_relay:
                    continue
                if '공지' in line or '로그인문제' in line:
                    break
                if should_ignore(line):
                    continue
                all_lines.add(line)
        except:
            continue

driver.quit()

print('\n=== 발견된 모든 라인 ===')
for line in sorted(all_lines):
    print(repr(line))