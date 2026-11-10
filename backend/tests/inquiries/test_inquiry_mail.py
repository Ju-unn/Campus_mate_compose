"""문의 알림 메일. 저장이 기준이라 메일이 실패해도 응답은 201 이다. 로그에는 본문 · 메일 주소가 없다."""
import asyncio
import logging
import smtplib
import threading

from inquiry_world import ME, USER_AUTH

GOOD = {"reason": "payment", "body": "하트가 안 들어왔어요", "reply_email": "me@example.com"}


def _post(client, **overrides):
    return client.post("/inquiries", json={**GOOD, **overrides}, headers=USER_AUTH)


def test_the_notification_goes_out_with_reply_to_set_to_the_users_address(client, world, smtp, password_settings):
    response = _post(client)

    assert response.status_code == 201
    (message,) = smtp.sent
    stored = world.inquiries[0]
    assert message["Reply-To"] == "me@example.com"
    assert message["To"] == "appmailerl4538@gmail.com"
    assert message["From"] == "appmailerl4538@gmail.com"
    assert message["Subject"] == f"[CampusMate 문의] 결제·하트 · 문의 번호 {stored['id'][:8]}"
    assert b"Reply-To: me@example.com" in message.as_bytes()   # 한글 제목 · 본문도 실제 메일 바이트로 만들어진다


def test_the_body_has_reason_text_reply_address_number_time_and_account(client, world, smtp, password_settings):
    _post(client)

    (message,) = smtp.sent
    text = message.get_content()
    stored = world.inquiries[0]
    assert "결제·하트" in text
    assert "하트가 안 들어왔어요" in text
    assert "me@example.com" in text
    assert stored["id"] in text
    assert "2026-11-10 14:00" in text      # 접수 시각(한국)
    assert ME in text                       # 계정 번호는 메일 본문에만 있다


def test_it_logs_in_with_the_app_password_over_ssl_on_gmail(client, world, smtp, password_settings):
    _post(client)

    assert smtp.connections == [("smtp.gmail.com", 465)]
    assert smtp.logins == [("appmailerl4538@gmail.com", "app-password")]


def test_without_a_password_no_mail_is_sent_and_a_warning_is_logged(client, world, smtp, caplog):
    with caplog.at_level(logging.WARNING):
        response = _post(client)

    assert response.status_code == 201
    assert smtp.connections == []
    assert any("문의 메일" in r.getMessage() and "건너" in r.getMessage() for r in caplog.records)


def test_a_mail_failure_is_only_logged_and_the_response_is_still_201(client, world, smtp, password_settings, caplog):
    smtp.fail = smtplib.SMTPAuthenticationError(535, b"bad credentials me@example.com")

    with caplog.at_level(logging.WARNING):
        response = _post(client)

    assert response.status_code == 201
    assert len(world.inquiries) == 1
    # 로그에는 문의 번호만 — 본문 · 메일 주소 · 서버가 돌려준 문장이 없다.
    logged = " ".join(r.getMessage() for r in caplog.records)
    assert world.inquiries[0]["id"] in logged
    assert "me@example.com" not in logged and "하트가 안" not in logged and "bad credentials" not in logged


def test_a_network_error_is_also_swallowed(client, world, smtp, password_settings):
    smtp.fail = TimeoutError("timed out")

    assert _post(client).status_code == 201


def test_the_mail_is_sent_off_the_event_loop_thread(client, world, smtp, password_settings, monkeypatch):
    """smtplib 는 막는 호출이다 — 이벤트 루프 스레드에서 돌면 그동안 서버 전체가 선다."""
    from app.inquiries import mailer
    loop_threads = []
    real_build = mailer.build_message

    def build_on_loop(*args, **kwargs):      # 코루틴 안(루프 스레드)에서 불린다
        loop_threads.append(threading.get_ident())
        return real_build(*args, **kwargs)

    monkeypatch.setattr(mailer, "build_message", build_on_loop)

    _post(client)

    assert len(loop_threads) == len(smtp.threads) == 1
    assert smtp.threads[0] != loop_threads[0]


def test_a_mail_that_hangs_is_given_up_on_and_the_response_is_still_201(client, world, monkeypatch, caplog):
    from app.inquiries import router

    async def hang(settings, **fields):
        await asyncio.sleep(3600)

    monkeypatch.setattr(router.mailer, "notify", hang)
    monkeypatch.setattr(router, "MAIL_WAIT_SECONDS", 0.01)

    with caplog.at_level(logging.WARNING):
        response = _post(client)

    assert response.status_code == 201
    logged = " ".join(r.getMessage() for r in caplog.records)
    assert world.inquiries[0]["id"] in logged and "TimeoutError" in logged
    assert "me@example.com" not in logged and "하트가 안" not in logged


def test_the_log_never_carries_the_body_or_address_on_success_either(client, world, smtp, password_settings, caplog):
    with caplog.at_level(logging.DEBUG):
        _post(client)

    logged = " ".join(r.getMessage() for r in caplog.records)
    assert "me@example.com" not in logged and "하트가 안" not in logged


def test_the_recipient_and_sender_come_from_settings(client, world, smtp):
    from app.core.deps import get_settings
    from app.main import app
    from inquiry_world import settings

    app.dependency_overrides[get_settings] = lambda: settings(
        inquiry_notify_to="ops@example.com", inquiry_smtp_user="bot@example.com", inquiry_smtp_password="pw")

    _post(client)

    (message,) = smtp.sent
    assert (message["To"], message["From"]) == ("ops@example.com", "bot@example.com")
    assert smtp.logins == [("bot@example.com", "pw")]
