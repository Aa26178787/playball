# test_parse.py
import sys
sys.path.insert(0, '.')

# crawl_relay_history의 함수만 직접 가져오기
from selenium import webdriver
from selenium.webdriver.chrome.options import Options
from selenium.webdriver.common.by import By
from selenium.webdriver.support.ui import WebDriverWait
from selenium.webdriver.support import expected_conditions as EC
import time, re

# crawl_relay_history.py에서 함수만 복사해서 사용
exec(open('crawl_relay_history.py').read().split('# 전체 종료 경기 크롤링')[0])

options = Options()
driver = webdriver.Chrome(options=options)

inning_data = crawl_relay_page(driver, '20260507HHHT02026')
driver.quit()

pitches = parse_relay(inning_data, 999)
for p in pitches:
    print(f"type={p['type']:2d} | {p['title']}")
print(f'\n총 {len(pitches)}개')

type_counts = {}
for p in pitches:
    t = p['type']
    type_counts[t] = type_counts.get(t, 0) + 1
print(f'타입별: {type_counts}')