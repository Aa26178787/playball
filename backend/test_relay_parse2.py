# test_relay_parse2.py
from selenium import webdriver
from selenium.webdriver.chrome.options import Options
from selenium.webdriver.common.by import By
from selenium.webdriver.support.ui import WebDriverWait
from selenium.webdriver.support import expected_conditions as EC
import time

options = Options()
driver = webdriver.Chrome(options=options)
driver.get('https://m.sports.naver.com/game/20260505NCSK02026/relay')
WebDriverWait(driver, 15).until(EC.presence_of_element_located((By.TAG_NAME, 'body')))
time.sleep(4)

inning_buttons = driver.find_elements(By.CLASS_NAME, 'SetTab_button_tab__XW5t5')
driver.execute_script("arguments[0].click();", inning_buttons[0])
time.sleep(2)
text = driver.execute_script("return document.body.innerText")
lines = [l.strip() for l in text.split('\n') if l.strip()]

# 200번부터 전체 출력
for i, line in enumerate(lines[200:280]):
    print(f'{i+200}: {repr(line)}')

driver.quit()