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
        driver_path = (shutil.which('chromium.chromedriver')
                       or '/snap/bin/chromium.chromedriver')
        profile = os.path.expanduser(f'~/snap/chromium/common/selenium-{os.getpid()}')
        os.makedirs(profile, exist_ok=True)
        options.add_argument(f'--user-data-dir={profile}')
        return webdriver.Chrome(service=Service(driver_path), options=options)

    from webdriver_manager.chrome import ChromeDriverManager
    return webdriver.Chrome(
        service=Service(ChromeDriverManager().install()), options=options)
