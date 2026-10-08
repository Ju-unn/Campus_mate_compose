"""옛 check · confirm(소셜 계정에 updateUser(email) 로 이메일을 붙이는 방식)은 폐기했다(지시문 05).

그 시험의 도메인 · 재가입 제한 · 다른 계정 검사 내용은 test_school_email_verify.py 로 옮겼다.
"""
import pytest
from fastapi.testclient import TestClient

from app.main import app
from app.signup_policy import SignupPolicy


@pytest.mark.parametrize("path", ["/school-email/check", "/school-email/confirm"])
def test_the_old_routes_are_gone(path):
    response = TestClient(app).post(path, headers={"Authorization": "Bearer user-token"}, json={})

    assert response.status_code == 404


def test_the_old_other_account_lookup_is_gone():
    # 다른 계정 판정은 이제 complete_school_email_verification 이 원자적으로 한다.
    assert not hasattr(SignupPolicy, "find_other_account_provider")
