"""배포 문서가 새 설정을 놓치지 않게 한다 — 이름과 설명만 있고 값은 없어야 한다(공개 저장소)."""
from pathlib import Path

BACKEND = Path(__file__).resolve().parents[1]


def test_env_example_names_the_kakao_admin_key_without_a_value():
    lines = (BACKEND / ".env.example").read_text(encoding="utf-8").splitlines()

    assert "KAKAO_ADMIN_KEY=" in lines


def test_deploy_doc_names_the_kakao_admin_key_and_says_to_register_it():
    text = (BACKEND / "DEPLOY.md").read_text(encoding="utf-8")

    assert "KAKAO_ADMIN_KEY" in text
    # §2 배포 명령 코드 블록에도 키 이름이 있으므로 설명 문단(굵은 키 이름으로 시작)만 고른다. 없으면 StopIteration 으로 실패.
    paragraph = next(block for block in text.split("\n\n") if block.startswith("**`KAKAO_ADMIN_KEY`"))
    assert "Secret Manager" in paragraph
    # 비어 있으면 탈퇴 때 카카오 연결 끊기만 건너뛴다 — 서버는 그대로 뜬다(settings.kakao_admin_key 기본값 "").
    assert "건너뛴다" in paragraph


APPLE_NAMES = ("APPLE_TEAM_ID", "APPLE_KEY_ID", "APPLE_PRIVATE_KEY")


def test_env_example_names_the_apple_revoke_settings_without_values():
    lines = (BACKEND / ".env.example").read_text(encoding="utf-8").splitlines()

    for name in APPLE_NAMES:
        assert f"{name}=" in lines


def test_deploy_doc_names_the_apple_private_key_secret_and_says_to_register_it():
    text = (BACKEND / "DEPLOY.md").read_text(encoding="utf-8")

    # 설명 문단(굵은 키 이름으로 시작)만 고른다. 없으면 StopIteration 으로 실패.
    paragraph = next(block for block in text.split("\n\n") if block.startswith("**`APPLE_PRIVATE_KEY`"))
    assert "Secret Manager" in paragraph
    assert "apple-sign-in-private-key" in paragraph
    for name in APPLE_NAMES:
        assert name in paragraph
    # 셋 중 하나라도 비면 탈퇴 때 애플 토큰 철회만 건너뛴다 — 서버는 그대로 뜬다.
    assert "건너뛴다" in paragraph


def test_deploy_doc_names_the_min_app_version_and_says_when_to_raise_it():
    text = (BACKEND / "DEPLOY.md").read_text(encoding="utf-8")

    # 설명 문단(굵은 키 이름으로 시작)만 고른다. 없으면 StopIteration 으로 실패.
    paragraph = next(block for block in text.split("\n\n") if block.startswith("**`MIN_APP_VERSION`"))
    # 고친 빌드가 두 스토어에서 공개되기 전에 올리면 사람들이 갈 곳 없이 막힌다.
    assert "두 스토어" in paragraph
    assert "공개" in paragraph
