# test_raw.py
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
]

inning_pattern = re.compile(r'^\d+회(초|말)\s+\S+\s+공격$')

for game_id in game_ids:
    print(f'\n{"="*60}')
    print(f'경기: {game_id}')
    print(f'{"="*60}')

    driver.get(f'https://m.sports.naver.com/game/{game_id}/relay')
    WebDriverWait(driver, 15).until(EC.presence_of_element_located((By.TAG_NAME, 'body')))
    time.sleep(4)

    inning_buttons = driver.find_elements(By.CLASS_NAME, 'SetTab_button_tab__XW5t5')
    if not inning_buttons:
        print('버튼 없음')
        continue

    # 마지막 이닝 클릭
    driver.execute_script("arguments[0].click();", inning_buttons[-1])
    time.sleep(2)

    text = driver.execute_script("return document.body.innerText")
    lines = [l.strip() for l in text.split('\n') if l.strip()]

    # 중계 시작점 찾기
    start = 0
    for idx, line in enumerate(lines):
        if inning_pattern.match(line):
            start = idx
            break

    for line in lines[start:]:
        print(repr(line))

driver.quit()