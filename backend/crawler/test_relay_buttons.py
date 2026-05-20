# test_relay_buttons.py
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

# 버튼 구조 확인
buttons = driver.find_elements(By.TAG_NAME, 'button')
for btn in buttons:
    txt = btn.text.strip()
    cls = btn.get_attribute('class')
    if txt:
        print(f'text={repr(txt)} class={cls}')

driver.quit()