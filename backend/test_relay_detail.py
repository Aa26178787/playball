# test_relay_detail.py
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

# 9회 버튼 클릭
inning_buttons = driver.find_elements(By.CLASS_NAME, 'SetTab_button_tab__XW5t5')
for btn in inning_buttons:
    if btn.text.strip() == '9회':
        driver.execute_script("arguments[0].click();", btn)
        break
time.sleep(2)

text = driver.execute_script("return document.body.innerText")
lines = [l.strip() for l in text.split('\n') if l.strip()]

inning_pattern = re.compile(r'^\d+회(초|말)\s+\S+\s+공격$')
start = 0
for i, line in enumerate(lines):
    if inning_pattern.match(line):
        start = i
        break

for i, line in enumerate(lines[start:start+300]):
    print(f'{i+start}: {repr(line)}')

driver.quit()