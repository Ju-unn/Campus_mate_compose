"""관리자 웹(브라우저) CORS(설계 10-18 §6-6). 모바일 앱은 Origin 을 보내지 않아 CORS 와 상관없다."""
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware


def install_admin_cors(app: FastAPI, origins: list[str]) -> None:
    """주소가 없으면 미들웨어를 아예 붙이지 않는다 — 지금 배포와 응답이 똑같다.
    토큰은 Authorization 헤더로만 오고 쿠키는 쓰지 않아 자격 증명(credentials)은 끈다. 관리자 API 는 GET · POST 뿐이다."""
    if not origins:
        return
    app.add_middleware(
        CORSMiddleware,
        allow_origins=origins,
        allow_methods=["GET", "POST"],
        allow_headers=["Authorization", "Content-Type"],
        allow_credentials=False,
    )
