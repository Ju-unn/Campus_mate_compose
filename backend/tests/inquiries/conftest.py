import threading

import httpx
import pytest
from fastapi.testclient import TestClient

from app.core.deps import get_client, get_now, get_settings
from app.main import app
from inquiry_world import NOW, InquiryWorld, settings


@pytest.fixture
def world() -> InquiryWorld:
    return InquiryWorld()


@pytest.fixture
def smtp(monkeypatch) -> "FakeSmtp":
    """smtplib.SMTP_SSL 을 가짜로 바꾼다 — 진짜 gmail 로 나가지 않는다. 보낸 메일은 smtp.sent 에 쌓인다."""
    fake = FakeSmtp()
    monkeypatch.setattr("app.inquiries.mailer.smtplib.SMTP_SSL", fake.connect)
    return fake


class FakeSmtp:
    def __init__(self) -> None:
        self.connections: list[tuple] = []
        self.logins: list[tuple[str, str]] = []
        self.sent = []
        self.fail: Exception | None = None
        self.threads: list[int] = []       # connect 가 불린 스레드

    def connect(self, host, port, **kwargs):
        self.connections.append((host, port))
        self.threads.append(threading.get_ident())
        if self.fail is not None:
            raise self.fail
        return self

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        return False

    def login(self, user, password):
        self.logins.append((user, password))

    def send_message(self, message):
        self.sent.append(message)


@pytest.fixture
def password_settings(client):
    """메일 비밀번호가 들어 있는 설정(운영과 같은 상태). 안 쓰면 비밀번호가 빈 로컬 상태다."""
    app.dependency_overrides[get_settings] = lambda: settings(inquiry_smtp_password="app-password")


@pytest.fixture
def client(world: InquiryWorld):
    http = httpx.AsyncClient(transport=httpx.MockTransport(world.handle))
    app.dependency_overrides[get_settings] = lambda: settings()
    app.dependency_overrides[get_client] = lambda: http
    app.dependency_overrides[get_now] = lambda: NOW
    yield TestClient(app)
    app.dependency_overrides.clear()
