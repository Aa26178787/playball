"""업로드 이미지 재인코딩 — EXIF(GPS·기기정보 등) 메타데이터 제거

Pillow로 픽셀만 다시 저장하면 EXIF가 탈락한다.
exif_transpose를 먼저 적용해 회전 정보를 픽셀에 반영한 뒤 제거해야
세로 사진이 눕는 문제가 없다.
"""
import io
from PIL import Image, ImageOps

_FMT = {'.jpg': 'JPEG', '.jpeg': 'JPEG', '.png': 'PNG', '.webp': 'WEBP'}
_MAX_IMAGE_PIXELS = 20_000_000


def strip_metadata(data: bytes, ext: str) -> bytes:
    """메타데이터 제거된 이미지 바이트 반환. 손상 이미지면 ValueError."""
    fmt = _FMT.get(ext.lower())
    if not fmt:
        raise ValueError(f'unsupported ext: {ext}')
    try:
        img = Image.open(io.BytesIO(data))
        if img.width * img.height > _MAX_IMAGE_PIXELS:
            raise ValueError('image dimensions are too large')
        img = ImageOps.exif_transpose(img)
        out = io.BytesIO()
        if fmt == 'JPEG':
            if img.mode not in ('RGB', 'L'):
                img = img.convert('RGB')
            img.save(out, format='JPEG', quality=90)
        else:
            img.save(out, format=fmt)
        return out.getvalue()
    except Exception as e:
        raise ValueError(f'invalid image: {e}')
