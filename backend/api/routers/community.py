from fastapi import APIRouter, HTTPException, Depends, UploadFile, File, Request
from pydantic import BaseModel
from typing import Optional
import os, uuid, shutil
from datetime import datetime, timedelta
from database.connection import get_connection
from api.routers.auth import get_current_user

POST_IMG_DIR = '/home/ubuntu/playball/backend/static/posts'
BASE_URL = 'http://168.107.61.147:8000'
os.makedirs(POST_IMG_DIR, exist_ok=True)

router = APIRouter()

# 조회수 throttle: (post_id, ip) → 마지막 조회 시각
_view_cache: dict = {}
_VIEW_COOLDOWN = timedelta(minutes=10)


class PostCreate(BaseModel):
    title: str
    content: str
    category: str = "자유"
    team_id: Optional[int] = None
    image_url: Optional[str] = None


class PostUpdate(BaseModel):
    title: str
    content: str


class CommentCreate(BaseModel):
    content: str


class ReportCreate(BaseModel):
    reason: str = "기타"


# ===== 게시글 =====

@router.get("/posts")
def get_posts(
    team_id: Optional[int] = None,
    category: Optional[str] = None,
    sort: str = "latest",
    q: Optional[str] = None,
    page: int = 1,
    limit: int = 20,
):
    conn = get_connection()
    if not conn:
        raise HTTPException(status_code=500, detail="DB 연결 실패")

    cur = conn.cursor()
    offset = (page - 1) * limit

    query = """
        SELECT p.id, p.title, p.category, p.views, p.likes,
               p.created_at, u.nickname, u.profile_image,
               t.name AS team_name, p.team_id,
               (SELECT COUNT(*) FROM comments c WHERE c.post_id = p.id) AS comment_count
        FROM posts p
        JOIN users u ON p.user_id = u.id
        LEFT JOIN teams t ON p.team_id = t.id
        WHERE 1=1
    """
    params = []

    if team_id:
        query += " AND p.team_id = %s"
        params.append(team_id)
    if category:
        query += " AND p.category = %s"
        params.append(category)
    if q:
        query += " AND (p.title ILIKE %s OR p.content ILIKE %s)"
        params.extend([f'%{q}%', f'%{q}%'])

    if sort == "hot":
        query += " ORDER BY p.likes DESC, p.created_at DESC"
    else:
        query += " ORDER BY p.created_at DESC"

    query += " LIMIT %s OFFSET %s"
    params.extend([limit, offset])

    cur.execute(query, params)
    rows = cur.fetchall()
    cur.close()
    conn.close()

    return {
        "page":  page,
        "limit": limit,
        "posts": [
            {
                "id":            r[0],
                "title":         r[1],
                "category":      r[2],
                "views":         r[3],
                "likes":         r[4],
                "created_at":    str(r[5]),
                "author":        r[6],
                "author_image":  r[7],
                "team_name":     r[8],
                "team_id":       r[9],
                "comment_count": r[10],
            }
            for r in rows
        ]
    }


@router.get("/posts/{post_id}")
def get_post_detail(post_id: int, request: Request):
    """게시글 상세 조회"""
    conn = get_connection()
    if not conn:
        raise HTTPException(status_code=500, detail="DB 연결 실패")

    cur = conn.cursor()

    # 조회수 throttle: 같은 IP에서 10분 내 재조회 시 증가 안 함
    ip = request.client.host if request.client else "unknown"
    cache_key = (post_id, ip)
    now = datetime.now()
    last_viewed = _view_cache.get(cache_key)
    if last_viewed is None or (now - last_viewed) > _VIEW_COOLDOWN:
        _view_cache[cache_key] = now
        cur.execute("UPDATE posts SET views = views + 1 WHERE id = %s", (post_id,))
        if len(_view_cache) > 10000:
            cutoff = now - _VIEW_COOLDOWN
            expired = [k for k, v in _view_cache.items() if v < cutoff]
            for k in expired:
                del _view_cache[k]

    # 선택적 인증: 댓글 liked_by_me 판단용
    current_user_id = None
    try:
        auth = request.headers.get('authorization') or request.headers.get('Authorization')
        if auth and auth.startswith('Bearer '):
            from jose import jwt
            from api.routers.auth import SECRET_KEY, ALGORITHM
            payload = jwt.decode(auth.split(' ')[1], SECRET_KEY, algorithms=[ALGORITHM])
            current_user_id = int(payload.get('sub', 0)) or None
    except Exception:
        pass

    # 게시글 조회 + 내 좋아요 여부
    cur.execute("""
        SELECT p.id, p.title, p.content, p.category,
               p.views, p.likes, p.created_at, p.updated_at,
               u.id AS user_id, u.nickname, u.profile_image,
               t.name AS team_name, p.image_url,
               EXISTS(SELECT 1 FROM post_likes pl WHERE pl.post_id = p.id AND pl.user_id = %s) AS liked_by_me
        FROM posts p
        JOIN users u ON p.user_id = u.id
        LEFT JOIN teams t ON p.team_id = t.id
        WHERE p.id = %s
    """, (current_user_id, post_id))

    row = cur.fetchone()
    if not row:
        raise HTTPException(status_code=404, detail="게시글을 찾을 수 없습니다")

    # 댓글 조회 + 좋아요 수 + liked_by_me
    cur.execute("""
        SELECT c.id, c.content, c.created_at,
               u.id AS user_id, u.nickname, u.profile_image,
               COUNT(cl.id) as likes_count,
               MAX(CASE WHEN cl.user_id = %s THEN 1 ELSE 0 END) as liked_by_me
        FROM comments c
        JOIN users u ON c.user_id = u.id
        LEFT JOIN comment_likes cl ON cl.comment_id = c.id
        WHERE c.post_id = %s
        GROUP BY c.id, c.content, c.created_at, u.id, u.nickname, u.profile_image
        ORDER BY c.created_at ASC
    """, (current_user_id, post_id))
    comments = cur.fetchall()

    conn.commit()
    cur.close()
    conn.close()

    return {
        "id":           row[0],
        "title":        row[1],
        "content":      row[2],
        "category":     row[3],
        "views":        row[4],
        "likes":        row[5],
        "created_at":   str(row[6]),
        "updated_at":   str(row[7]),
        "user_id":      row[8],
        "author":       row[9],
        "author_image": row[10],
        "team_name":    row[11],
        "image_url":    row[12],
        "liked_by_me":  row[13],
        "comments": [
            {
                "id":           c[0],
                "content":      c[1],
                "created_at":   str(c[2]),
                "user_id":      c[3],
                "author":       c[4],
                "author_image": c[5],
                "likes_count":  c[6],
                "liked_by_me":  bool(c[7]),
            }
            for c in comments
        ]
    }


@router.post("/posts")
def create_post(body: PostCreate, current_user: dict = Depends(get_current_user)):
    """게시글 작성"""
    conn = get_connection()
    if not conn:
        raise HTTPException(status_code=500, detail="DB 연결 실패")

    cur = conn.cursor()
    cur.execute("SELECT phone_verified FROM users WHERE id = %s", (current_user["user_id"],))
    row = cur.fetchone()
    if not row or not row[0]:
        cur.close()
        conn.close()
        raise HTTPException(status_code=403, detail="phone_not_verified")

    cur.execute("""
        INSERT INTO posts (user_id, team_id, title, content, category, image_url)
        VALUES (%s, %s, %s, %s, %s, %s)
        RETURNING id
    """, (
        current_user["user_id"], body.team_id,
        body.title, body.content, body.category, body.image_url
    ))

    post_id = cur.fetchone()[0]
    conn.commit()
    cur.close()
    conn.close()

    return {"message": "게시글 작성 완료", "post_id": post_id}


@router.put("/posts/{post_id}")
def update_post(post_id: int, body: PostUpdate, current_user: dict = Depends(get_current_user)):
    """게시글 수정"""
    conn = get_connection()
    if not conn:
        raise HTTPException(status_code=500, detail="DB 연결 실패")

    cur = conn.cursor()

    # 작성자 확인
    cur.execute("SELECT user_id FROM posts WHERE id = %s", (post_id,))
    row = cur.fetchone()
    if not row:
        raise HTTPException(status_code=404, detail="게시글을 찾을 수 없습니다")
    if row[0] != current_user["user_id"]:
        raise HTTPException(status_code=403, detail="수정 권한이 없습니다")

    cur.execute("""
        UPDATE posts SET title = %s, content = %s, updated_at = NOW()
        WHERE id = %s
    """, (body.title, body.content, post_id))

    conn.commit()
    cur.close()
    conn.close()
    return {"message": "게시글 수정 완료"}


@router.delete("/posts/{post_id}")
def delete_post(post_id: int, current_user: dict = Depends(get_current_user)):
    """게시글 삭제"""
    conn = get_connection()
    if not conn:
        raise HTTPException(status_code=500, detail="DB 연결 실패")

    cur = conn.cursor()

    cur.execute("SELECT user_id FROM posts WHERE id = %s", (post_id,))
    row = cur.fetchone()
    if not row:
        raise HTTPException(status_code=404, detail="게시글을 찾을 수 없습니다")
    if row[0] != current_user["user_id"]:
        raise HTTPException(status_code=403, detail="삭제 권한이 없습니다")

    cur.execute("DELETE FROM comments WHERE post_id = %s", (post_id,))
    cur.execute("DELETE FROM post_likes WHERE post_id = %s", (post_id,))
    cur.execute("DELETE FROM posts WHERE id = %s", (post_id,))

    conn.commit()
    cur.close()
    conn.close()
    return {"message": "게시글 삭제 완료"}


@router.post("/posts/{post_id}/like")
def toggle_like(post_id: int, current_user: dict = Depends(get_current_user)):
    """좋아요 토글"""
    conn = get_connection()
    if not conn:
        raise HTTPException(status_code=500, detail="DB 연결 실패")

    cur = conn.cursor()

    # 이미 좋아요 했는지 확인
    cur.execute("""
        SELECT id FROM post_likes
        WHERE post_id = %s AND user_id = %s
    """, (post_id, current_user["user_id"]))

    if cur.fetchone():
        # 좋아요 취소
        cur.execute("""
            DELETE FROM post_likes WHERE post_id = %s AND user_id = %s
        """, (post_id, current_user["user_id"]))
        cur.execute("UPDATE posts SET likes = likes - 1 WHERE id = %s", (post_id,))
        message = "좋아요 취소"
    else:
        # 좋아요 추가
        cur.execute("""
            INSERT INTO post_likes (post_id, user_id) VALUES (%s, %s)
        """, (post_id, current_user["user_id"]))
        cur.execute("UPDATE posts SET likes = likes + 1 WHERE id = %s", (post_id,))
        message = "좋아요 추가"

    conn.commit()
    cur.close()
    conn.close()
    return {"message": message}


# ===== 댓글 =====

@router.post("/posts/{post_id}/comments")
def create_comment(post_id: int, body: CommentCreate, current_user: dict = Depends(get_current_user)):
    """댓글 작성"""
    conn = get_connection()
    if not conn:
        raise HTTPException(status_code=500, detail="DB 연결 실패")

    cur = conn.cursor()

    cur.execute("SELECT user_id, title FROM posts WHERE id = %s", (post_id,))
    post_row = cur.fetchone()
    if not post_row:
        raise HTTPException(status_code=404, detail="게시글을 찾을 수 없습니다")
    post_author_id, post_title = post_row

    # 댓글 작성자 닉네임
    cur.execute("SELECT nickname FROM users WHERE id = %s", (current_user["user_id"],))
    nick_row = cur.fetchone()
    commenter_nickname = nick_row[0] if nick_row else "누군가"

    cur.execute("""
        INSERT INTO comments (post_id, user_id, content)
        VALUES (%s, %s, %s)
        RETURNING id
    """, (post_id, current_user["user_id"], body.content))

    comment_id = cur.fetchone()[0]
    conn.commit()
    cur.close()
    conn.close()

    # 게시글 작성자에게 알림 (본인 댓글 제외)
    if post_author_id != current_user["user_id"]:
        try:
            from api.fcm_service import notify_new_comment
            notify_new_comment(post_author_id, post_id, post_title or "", commenter_nickname)
        except Exception:
            pass

    return {"message": "댓글 작성 완료", "comment_id": comment_id}


@router.post("/posts/{post_id}/report")
def report_post(post_id: int, body: ReportCreate, current_user: dict = Depends(get_current_user)):
    conn = get_connection()
    if not conn:
        raise HTTPException(status_code=500, detail="DB 연결 실패")
    cur = conn.cursor()

    cur.execute("SELECT id FROM posts WHERE id = %s", (post_id,))
    if not cur.fetchone():
        cur.close()
        conn.close()
        raise HTTPException(status_code=404, detail="게시글을 찾을 수 없습니다")

    cur.execute(
        """INSERT INTO post_reports (post_id, user_id, reason)
           VALUES (%s, %s, %s)
           ON CONFLICT (post_id, user_id) DO NOTHING""",
        (post_id, current_user["user_id"], body.reason)
    )
    conn.commit()
    cur.close()
    conn.close()
    return {"message": "신고가 접수되었습니다"}


@router.get("/my-posts")
def get_my_posts(page: int = 1, limit: int = 20, current_user: dict = Depends(get_current_user)):
    conn = get_connection()
    if not conn:
        raise HTTPException(status_code=500, detail="DB 연결 실패")
    cur = conn.cursor()
    offset = (page - 1) * limit
    cur.execute("""
        SELECT p.id, p.title, p.category, p.views, p.likes, p.created_at,
               (SELECT COUNT(*) FROM comments c WHERE c.post_id = p.id)
        FROM posts p
        WHERE p.user_id = %s
        ORDER BY p.created_at DESC
        LIMIT %s OFFSET %s
    """, (current_user["user_id"], limit, offset))
    rows = cur.fetchall()
    cur.close()
    conn.close()
    return {"posts": [
        {"id": r[0], "title": r[1], "category": r[2], "views": r[3],
         "likes": r[4], "created_at": str(r[5]), "comment_count": r[6]}
        for r in rows
    ]}


@router.delete("/comments/{comment_id}")
def delete_comment(comment_id: int, current_user: dict = Depends(get_current_user)):
    """댓글 삭제"""
    conn = get_connection()
    if not conn:
        raise HTTPException(status_code=500, detail="DB 연결 실패")

    cur = conn.cursor()

    cur.execute("SELECT user_id FROM comments WHERE id = %s", (comment_id,))
    row = cur.fetchone()
    if not row:
        raise HTTPException(status_code=404, detail="댓글을 찾을 수 없습니다")
    if row[0] != current_user["user_id"]:
        raise HTTPException(status_code=403, detail="삭제 권한이 없습니다")

    cur.execute("DELETE FROM comments WHERE id = %s", (comment_id,))
    conn.commit()
    cur.close()
    conn.close()
    return {"message": "댓글 삭제 완료"}

@router.get('/my-comments')
def get_my_comments(page: int = 1, limit: int = 20, current_user: dict = Depends(get_current_user)):
    conn = get_connection()
    if not conn:
        raise HTTPException(status_code=500, detail='DB 연결 실패')
    cur = conn.cursor()
    offset = (page - 1) * limit
    cur.execute("""
        SELECT c.id, c.content, c.created_at,
               p.id AS post_id, p.title AS post_title
        FROM comments c
        JOIN posts p ON c.post_id = p.id
        WHERE c.user_id = %s
        ORDER BY c.created_at DESC
        LIMIT %s OFFSET %s
    """, (current_user['user_id'], limit, offset))
    rows = cur.fetchall()
    cur.close()
    conn.close()
    return {'comments': [
        {'id': r[0], 'content': r[1], 'created_at': str(r[2]),
         'post_id': r[3], 'post_title': r[4]}
        for r in rows
    ]}


@router.post("/comments/{comment_id}/like")
def toggle_comment_like(comment_id: int, current_user: dict = Depends(get_current_user)):
    """댓글 좋아요 토글"""
    conn = get_connection()
    if not conn:
        raise HTTPException(status_code=500, detail="DB 연결 실패")
    cur = conn.cursor()
    cur.execute("SELECT id FROM comments WHERE id = %s", (comment_id,))
    if not cur.fetchone():
        cur.close(); conn.close()
        raise HTTPException(status_code=404, detail="댓글을 찾을 수 없습니다")
    cur.execute("SELECT id FROM comment_likes WHERE comment_id = %s AND user_id = %s",
                (comment_id, current_user["user_id"]))
    if cur.fetchone():
        cur.execute("DELETE FROM comment_likes WHERE comment_id = %s AND user_id = %s",
                    (comment_id, current_user["user_id"]))
        message = "좋아요 취소"
    else:
        cur.execute("INSERT INTO comment_likes (comment_id, user_id) VALUES (%s, %s)",
                    (comment_id, current_user["user_id"]))
        message = "좋아요 추가"
    conn.commit()
    cur.execute("SELECT COUNT(*) FROM comment_likes WHERE comment_id = %s", (comment_id,))
    count = cur.fetchone()[0]
    cur.close(); conn.close()
    return {"message": message, "likes_count": count}


@router.get("/my-likes")
def get_my_likes(page: int = 1, limit: int = 20, current_user: dict = Depends(get_current_user)):
    """내가 좋아요한 게시글"""
    conn = get_connection()
    if not conn:
        raise HTTPException(status_code=500, detail="DB 연결 실패")
    cur = conn.cursor()
    offset = (page - 1) * limit
    cur.execute("""
        SELECT p.id, p.title, p.category, p.views, p.likes, p.created_at,
               u.nickname, (SELECT COUNT(*) FROM comments c WHERE c.post_id = p.id)
        FROM post_likes pl
        JOIN posts p ON pl.post_id = p.id
        JOIN users u ON p.user_id = u.id
        WHERE pl.user_id = %s
        ORDER BY pl.created_at DESC
        LIMIT %s OFFSET %s
    """, (current_user["user_id"], limit, offset))
    rows = cur.fetchall()
    cur.close(); conn.close()
    return {"posts": [
        {"id": r[0], "title": r[1], "category": r[2], "views": r[3],
         "likes": r[4], "created_at": str(r[5]), "author": r[6], "comment_count": r[7]}
        for r in rows
    ]}


@router.post('/posts/upload-image')
async def upload_post_image(
    file: UploadFile = File(...),
    current_user: dict = Depends(get_current_user)
):
    ext = os.path.splitext(file.filename or 'img.jpg')[1].lower()
    if ext not in ('.jpg', '.jpeg', '.png', '.webp'):
        raise HTTPException(status_code=400, detail='jpg/png/webp만 허용됩니다')
    filename = f"post_{current_user['user_id']}_{uuid.uuid4().hex[:8]}{ext}"
    path = os.path.join(POST_IMG_DIR, filename)
    with open(path, 'wb') as f:
        shutil.copyfileobj(file.file, f)
    url = f"{BASE_URL}/static/posts/{filename}"
    return {'image_url': url}
