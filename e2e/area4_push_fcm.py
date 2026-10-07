"""영역 4 알림(PUSH) — FCM 으로 직접 보낸 알림 둘: E-PUSH-56 · 57(묶음 area4-push-fcm). 폰 A 한 대. 앱 쪽은 frontend/integration_test/area4_push_fcm.dart 의 같은 번호.
기대값은 바탕화면 E2E_최종테스트_시나리오.md 영역 4 의 그 줄이되, 코드가 다르면 코드가 기준이다(근거: frontend/lib/core/push/push_route.dart).

  E-PUSH-56  data.route = zzz(모르는 값) 알림을 누르면 앱만 앞으로 오고 보던 화면(홈) 그대로 — 대화 목록 · 방 · 받은 리뷰가 안 뜬다.
  E-PUSH-57  data.route = chat 인데 match_id 가 없으면 대화 목록(13)으로 간다.

서버를 거치지 않고 이 PC 의 `gcloud` 로그인(사용자 계정)으로 FCM HTTP v1 `messages:send` 를 직접 부른다 — 본문은 backend/app/cards/push.py FcmSender.send 와 같은 모양
(notification 제목 · 본문 + data + android.priority high). 사용자가 이 방식을 허락했다(2026-10-07). 지키는 것:
  ① 액세스 토큰 · 프로젝트 주소 · FCM 응답 본문은 로그 · 결과 줄 · 메모 · 코드 어디에도 남기지 않는다 — 실패 이유는 상태 숫자와 짧은 말뿐이다.
     요청은 재시도하지 않는다(tools.call 의 재시도 기록에 경로, 곧 프로젝트 주소가 남는다).
  ② 받는 곳은 이번 실행이 만든 계정의 기기 토큰 한 개뿐이다 — 토큰이 정확히 한 행이 아니면 보내지 않고 blocked.
  ③ 서울 08~22시에만 돈다(푸시 시험).
  ④ gcloud 가 없거나 로그인 · 프로젝트가 없거나 발송이 거절되면 blocked(fail 이 아니다) — 이유만 적는다.
"""

import functools
import secrets
import shutil
import subprocess
import time

from e2e import area1, area3_phone, notify, tools
from e2e.area1 import Check, _app, _rows
from e2e.area2_phone3 import _wait_for, notice_memo
from e2e.area3_phone import MISSING, _permitted
from e2e.area4_push import TOKEN_WAIT
from e2e.tools import Blocked

FCM_URL = 'https://fcm.googleapis.com/v1/projects/{project}/messages:send'
GCLOUD_WAIT = 60  # gcloud 한 번의 상한(초)
APP_WAIT = 90  # 앱이 눌린 뒤 화면을 읽고 말하기를 기다리는 초
CASE_LIMIT = 600
BODY = 'E2E 직접 발송 시험'  # 알림 본문 — 제목에 무작위 꼬리를 붙여 알림창에서 이 알림만 고른다


# ── gcloud · FCM ───────────────────────────────────────────────────────────────────────────────────

def _gcloud(*args):
    """gcloud 한 줄의 출력(앞뒤 공백 뺌). 못 부르거나 실패하면 이유만 담은 [Blocked] — 출력 · 오류 본문은 담지 않는다(토큰 · 프로젝트 주소가 들 수 있다)."""
    exe = shutil.which('gcloud')
    if not exe:
        raise Blocked('gcloud 가 이 PC 에 없음')
    try:
        done = subprocess.run([exe, *args], capture_output=True, text=True, timeout=GCLOUD_WAIT, check=False)
    except (OSError, subprocess.SubprocessError):
        raise Blocked('gcloud 를 못 돌림') from None
    out = (done.stdout or '').strip()
    if done.returncode != 0 or not out:
        raise Blocked(f'gcloud {args[0]} 실패(종료 코드 {done.returncode}) — 로그인 · 프로젝트 설정 확인')
    return out


def credentials():
    """(액세스 토큰, 프로젝트). 둘 다 이 가설 안에서만 쓰고 어디에도 적지 않는다."""
    return _gcloud('auth', 'print-access-token'), _gcloud('config', 'get-value', 'project')


def fcm_send(creds, device_token, title, body, data):
    """FCM v1 로 알림 한 건 — 기기 토큰 하나에게만. 거절 · 실패는 상태 숫자만 담은 [Blocked]."""
    access, project = creds
    message = {'token': device_token, 'notification': {'title': title, 'body': body},
               'data': {key: str(value) for key, value in data.items()}, 'android': {'priority': 'high'}}
    try:
        status = tools.call('POST', FCM_URL.format(project=project), {'Authorization': f'Bearer {access}'}, {'message': message}, retry=False)[0]
    except Exception:  # noqa: BLE001 — 예외 글에 주소가 들 수 있어 종류도 안 남긴다
        raise Blocked('FCM 호출이 안 닿음(네트워크)') from None
    if status in (401, 403):
        raise Blocked(f'FCM 발송 권한 거절({status}) — gcloud 계정 권한 확인')
    if status == 404:
        raise Blocked('FCM 이 이 기기 토큰을 모름(404) — 앱을 다시 켜 토큰을 새로 올려야 한다')
    if status >= 300:
        raise Blocked(f'FCM 발송 실패({status})')


# ── 가설 ───────────────────────────────────────────────────────────────────────────────────────────

def _run(run, phone, route, judge, send=fcm_send, creds=credentials):
    notify.require_daytime()
    notify.ensure_delivery(phone.serial)  # 푸시 연결이 죽은 폰이면 "알림이 안 왔다" 를 앱 탓으로 읽게 된다
    secret = creds()  # 계정을 만들기 전에 — gcloud 가 안 되면 아무것도 안 만든다
    check = Check()
    me = area3_phone._person(run)
    token = run.link(me['email'])
    title = f'E2E-{secrets.token_hex(3)}'
    seen = {}

    def hold(said):
        if not _wait_for(lambda: _rows(run, f"push_tokens?profile_id=eq.{me['id']}&select=token"), TOKEN_WAIT):
            raise Blocked(f'{TOKEN_WAIT}초 안에 기기 토큰이 서버에 안 올라옴 — 알림 권한 · FCM 확인')
        rows = _rows(run, f"push_tokens?profile_id=eq.{me['id']}&select=token")
        if len(rows) != 1:
            raise Blocked(f'이 계정의 기기 토큰이 {len(rows)}개 — 시험 폰 한 대에만 보내야 해서 보내지 않음')
        before = notify.read_notifications(phone.serial)
        notify.background(phone.serial)  # 앱이 앞에 있으면 배너가 안 뜬다
        send(secret, rows[0]['token'], title, BODY, {'route': route})
        new = notify.wait_new(phone.serial, before, seconds=notify.NOTICE_WAIT, match=lambda n: (n.title, n.text) == (title, BODY))
        seen['arrived'] = any((n.title, n.text) == (title, BODY) for n in new)
        check.that(seen['arrived'], f'{notify.NOTICE_WAIT}초 안에 알림 "{title}" 없음(새 알림 {len(new)}건: {notice_memo(new)})')
        if seen['arrived']:
            notify.tap_notification(phone.serial, title, BODY)  # 앱이 앞으로 안 오면 [Blocked]
            time.sleep(1)

    said = _app(check, phone(midway=hold, token_hash=token, phase='hold', route=route))
    if seen.get('arrived'):
        judge(check, said)
    return check.result('FCM 직접 발송 1건(서버 · 카드 지급 없음) — 토큰 · 프로젝트 주소는 남기지 않는다')


def _judge_56(check, said):
    """앱이 앞으로 왔고(누르기가 끝났다) 홈이 그대로, 다른 화면은 안 뜸."""
    where = {key: said.get(key, MISSING) for key in ('home', 'conversations', 'room', 'reviews')}
    check.that(where['home'] is True, f'모르는 route 알림을 누른 뒤 홈이 안 보임({where}) — 보던 화면을 빼앗겼다')
    for key in ('conversations', 'room', 'reviews'):
        check.that(where[key] is False, f'모르는 route 알림을 눌렀는데 {key} 화면이 뜸({where[key]})')


def _judge_57(check, said):
    """match_id 없는 chat 알림 → 대화 목록, 방은 안 열림."""
    check.that(said.get('conversations') is True, f"대화 목록이 안 열림({said.get('conversations', MISSING)})")
    check.that(said.get('room') is False, f"방 없는 chat 알림인데 대화방이 열림({said.get('room', MISSING)})")


def _case(route, judge):
    @functools.wraps(_run)
    def case(run, phone):
        return _run(run, phone, route, judge)
    return _permitted(case)


PHONE = {'E-PUSH-56': _case('zzz', _judge_56), 'E-PUSH-57': _case('chat', _judge_57)}

area1.PHONE.update(PHONE)
area1.BUNDLES['area4-push-fcm'] = list(PHONE)
tools.CASE_LIMITS.update({case: CASE_LIMIT for case in PHONE})
