# test_debug.py
from selenium import webdriver
from selenium.webdriver.chrome.options import Options
from selenium.webdriver.common.by import By
from selenium.webdriver.support.ui import WebDriverWait
from selenium.webdriver.support import expected_conditions as EC
import time, re

options = Options()
driver = webdriver.Chrome(options=options)
driver.get('https://m.sports.naver.com/game/20260507HHHT02026/relay')
WebDriverWait(driver, 15).until(EC.presence_of_element_located((By.TAG_NAME, 'body')))
time.sleep(4)

inning_buttons = driver.find_elements(By.CLASS_NAME, 'SetTab_button_tab__XW5t5')
driver.execute_script("arguments[0].click();", inning_buttons[0])
time.sleep(2)

text = driver.execute_script("return document.body.innerText")
lines = [l.strip() for l in text.split('\n') if l.strip()]
driver.quit()

inning_pattern = re.compile(r'^(\d+)회(초|말)\s+\S+\s+공격$')
batter_pattern = re.compile(r'^(.+?)(\d+)번타자타율\s+([\d.]+)$')
pitch_info_pattern = re.compile(r'^(\d+)km/h(.+)$')

# 중계 시작점 찾기
start = 0
for idx, line in enumerate(lines):
    if inning_pattern.match(line):
        start = idx
        break

# 1회 데이터 raw 출력
print('=== 1회 raw 데이터 ===')
for i, line in enumerate(lines[start:start+50]):
    is_digit = line.isdigit()
    next_is_gu = (start+i+1 < len(lines)) and lines[start+i+1] == '구'
    bm = batter_pattern.match(line)
    print(f'{i}: {repr(line)} | digit={is_digit} next=구:{next_is_gu} batter={bool(bm)}')