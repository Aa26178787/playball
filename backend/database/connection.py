 
import psycopg2
from psycopg2.extras import RealDictCursor

DB_CONFIG = {
    "host": "localhost",
    "port": 5432,
    "database": "playball",
    "user": "playball_user",  # 설치할 때 설정한 사용자 이름
    "password": "playball1234"  # 설치할 때 설정한 비밀번호
}

def get_connection():
    """DB 연결 반환"""
    try:
        conn = psycopg2.connect(**DB_CONFIG)
        return conn
    except Exception as e:
        print(f"DB 연결 오류: {e}")
        return None


def test_connection():
    """DB 연결 테스트"""
    conn = get_connection()
    if conn:
        print("DB 연결 성공!")
        conn.close()
    else:
        print("DB 연결 실패!")


if __name__ == "__main__":
    test_connection()