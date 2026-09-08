import io
import os

import pytest
from PIL import Image
from fastapi.testclient import TestClient

os.environ.setdefault('JWT_SECRET_KEY', 'test-only-secret')

from api import cache, email_service, image_utils, sms_service
from api.routers import email_verify, password_reset
from api.routers.auth import validate_password
from api.main import app


def test_verification_codes_are_six_digits():
    generators = (
        sms_service.generate_code,
        email_verify._generate_code,
        password_reset._generate_code,
    )
    for generator in generators:
        values = {generator() for _ in range(20)}
        assert all(len(value) == 6 and value.isdigit() for value in values)


def test_verification_providers_fail_closed_without_credentials(monkeypatch):
    monkeypatch.setattr(email_service, 'EMAIL_USER', '')
    monkeypatch.setattr(email_service, 'EMAIL_PASS', '')
    monkeypatch.setattr(email_service, '_ALLOW_DEV_CODES', False)
    monkeypatch.setattr(sms_service, 'API_KEY', '')
    monkeypatch.setattr(sms_service, 'API_SECRET', '')
    monkeypatch.setattr(sms_service, 'SENDER', '')
    monkeypatch.setattr(sms_service, '_ALLOW_DEV_CODES', False)

    assert email_service.send_verification_email('user@example.com', '123456') is False
    assert sms_service.send_verification_sms('01000000000', '123456') is False


def test_reset_password_uses_registration_password_policy():
    with pytest.raises(Exception):
        validate_password('123456')
    validate_password('baseball9')


def test_image_pixel_limit_is_enforced(monkeypatch):
    image = Image.new('RGB', (11, 10))
    data = io.BytesIO()
    image.save(data, format='PNG')
    monkeypatch.setattr(image_utils, '_MAX_IMAGE_PIXELS', 100)

    with pytest.raises(ValueError, match='dimensions'):
        image_utils.strip_metadata(data.getvalue(), '.png')


def test_cache_has_a_hard_entry_limit(monkeypatch):
    with cache._global_lock:
        cache._store.clear()
        cache._key_locks.clear()
    monkeypatch.setattr(cache, '_MAX_CACHE_ENTRIES', 2)

    cache.cache_set('a', 1, 60)
    cache.cache_set('b', 2, 60)
    cache.cache_set('c', 3, 60)

    assert len(cache._store) <= 2


def test_public_list_limits_are_validated_before_database_access():
    client = TestClient(app)
    assert client.get('/players/hitters?limit=0').status_code == 422
    assert client.get('/community/posts?page=0').status_code == 422
    assert client.get('/historical/leaders?limit=1000').status_code == 422
