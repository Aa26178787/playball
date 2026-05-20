# test_position.py
import re

# (으)를 이스케이프
position_change_pattern = re.compile(r'^.+\(으\)로 수비위치 변경$')

test_lines = [
    '2루수 이도윤 : 유격수(으)로 수비위치 변경',
    '대주자 채현우 : 우익수(으)로 수비위치 변경',
    '좌익수 천재환 : 중견수(으)로 수비위치 변경',
    '유격수 박민 : 3루수(으)로 수비위치 변경',
    '대타 고종욱 : 지명타자(으)로 수비위치 변경',
]

for line in test_lines:
    m = position_change_pattern.search(line)
    print(f'{bool(m)} | {line}')