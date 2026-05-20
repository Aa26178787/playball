# test_one.py
from selenium import webdriver
from selenium.webdriver.chrome.options import Options
from selenium.webdriver.common.by import By
from selenium.webdriver.support.ui import WebDriverWait
from selenium.webdriver.support import expected_conditions as EC
import time, re, sys

src = open('crawl_relay_history.py', encoding='utf-8').read()
exec(src.split('# 전체 종료 경기 크롤링')[0])

options = Options()
driver = webdriver.Chrome(options=options)
inning_data = crawl_relay_page(driver, '20260507HHHT02026')
driver.quit()

pitches = parse_relay(inning_data, 999)
type_counts = {}
for p in pitches:
    type_counts[p['type']] = type_counts.get(p['type'], 0) + 1
print(f'총 {len(pitches)}개 | 타입별: {type_counts}')
for p in pitches[:30]:
    print(f"type={p['type']:2d} | {p['title']}")