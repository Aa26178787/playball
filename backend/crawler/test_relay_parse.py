# test_relay_parse.py
from selenium import webdriver
from selenium.webdriver.chrome.options import Options
from selenium.webdriver.common.by import By
from selenium.webdriver.support.ui import WebDriverWait
from selenium.webdriver.support import expected_conditions as EC
import time, re

options = Options()
driver = webdriver.Chrome(options=options)
driver.get('https://m.sports.naver.com/game/20260505NCSK02026/relay')
WebDriverWait(driver, 15).until(EC.presence_of_element_located((By.TAG_NAME, 'body')))
time.sleep(4)

# 1회 버튼 클릭
inning_buttons = driver.find_elements(By.CLASS_NAME, 'SetTab_button_tab__XW5t5')
print(f'버튼 수: {len(inning_buttons)}')

if inning_buttons:
    driver.execute_script("arguments[0].click();", inning_buttons[0])
    time.sleep(2)
    text = driver.execute_script("return document.body.innerText")
    lines = [l.strip() for l in text.split('\n') if l.strip()]
    
    # 중계 섹션 찾기
    inning_pattern = re.compile(r'^(\d+)회(초|말)\s+\S+\s+공격$')
    for i, line in enumerate(lines):
        if inning_pattern.match(line) or '번타자' in line or 'Km/h' in line or '아웃' in line or '안타' in line:
            print(f'{i}: {repr(line)}')

driver.quit()