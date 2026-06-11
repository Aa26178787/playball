"""셀레늄 크롬 드라이버 공용 생성기 — ARM(A1)/x86 분기.

ARM(aarch64): 공식 chromedriver 미배포 → snap chromium 동봉 드라이버 사용.
⚠️ binary_location 지정 금지(snap 내부에서 짝 브라우저 자동 인지 — 주입 시 즉사),
프로필은 snap 가시 경로(~/snap/chromium/common) 필수(호스트 /tmp 접근 불가).
x86: webdriver_manager 기존 경로 유지.
"""


def arm_or_wdm_chrome(options):
    """호출측이 구성한 Options로 webdriver.Chrome 생성."""
    import os
    import platform
    import shutil

    from selenium import webdriver
    from selenium.webdriver.chrome.service import Service

    if platform.machine() in ('aarch64', 'arm64'):
        import glob
        import tempfile
        import time

        driver_path = (shutil.which('chromium.chromedriver')
                       or '/snap/bin/chromium.chromedriver')
        base = os.path.expanduser('~/snap/chromium/common')
        os.makedirs(base, exist_ok=True)
        # 프로필 = 드라이버 인스턴스별 고유 (PID 기준이면 같은 프로세스의 연속/병렬
        # 생성이 "user data dir already in use"로 즉사). 1시간 지난 잔존물 청소.
        now = time.time()
        for d in glob.glob(os.path.join(base, 'selenium-*')):
            try:
                if now - os.path.getmtime(d) > 3600:
                    shutil.rmtree(d, ignore_errors=True)
            except OSError:
                pass
        profile = tempfile.mkdtemp(prefix='selenium-', dir=base)
        options.add_argument(f'--user-data-dir={profile}')
        return webdriver.Chrome(service=Service(driver_path), options=options)

    from webdriver_manager.chrome import ChromeDriverManager
    return webdriver.Chrome(
        service=Service(ChromeDriverManager().install()), options=options)
