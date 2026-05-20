from selenium import webdriver
from selenium.webdriver.chrome.options import Options
from selenium.webdriver.common.by import By
import time

options = Options()
# 헤드리스 끄고 실제 브라우저로 확인

driver = webdriver.Chrome(options=options)
driver.get('https://m.sports.naver.com/game/20260505NCSK02026/relay')
time.sleep(5)

text = driver.find_element(By.TAG_NAME, 'body').text
lines = [l.strip() for l in text.split('\n') if l.strip()]
for i, line in enumerate(lines):
    print(f'{i}: {repr(line)}')

driver.quit()