from pydantic_settings import BaseSettings


class GraduateSettings(BaseSettings):
    """졸업생 인증 서버 플래그. 공유 파일 settings.py 를 건드리지 않으려고 AdminWebSettings 처럼 따로 둔다.

    기본 꺼짐(결정 D14): 배포와 공개를 떼어 놓는다. 켜는 것은 출시 날 환경변수 한 줄(GRADUATE_VERIFICATION_ENABLED=true)이고
    끄면 새 앱도 지금 관문(학교 메일)으로 돌아간다."""

    graduate_verification_enabled: bool = False


def graduate_enabled() -> bool:
    # 요청마다 읽는다(환경변수 한 줄이라 싸다). 캐시하지 않아 시험이 환경변수로 켜고 끈다.
    return GraduateSettings().graduate_verification_enabled
