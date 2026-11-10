"""휴대폰 문자 인증(04-1)을 거쳐야 하는 가설의 PC 쪽 도구 — 로컬 서버의 가짜 발송기 로그에서 인증번호를 읽어 앱에 건넨다.

규칙(사용자 11-11): 문자가 나갈 수 있는 시험은 **무작위 번호를 쓰지 않는다.** 번호는 시험 번호 하나뿐이고(환경값 `E2E_TEST_PHONE`
또는 비밀 폴더의 `e2e-test-phone.txt`), 그 값은 코드 · 로그 · 출력 · 오류 문구 어디에도 적지 않는다.
**운영 서버를 대상으로는 "인증번호 받기" 를 누르지 않는다** — 로컬(SUPABASE_URL 이 운영이 아님)일 때만 돈다.

로컬 서버를 띄울 때 로그를 파일로 남긴다(`uvicorn app.main:app … > server.log 2>&1`, 파일 이름을 환경값 또는 e2e env 의
`E2E_SERVER_LOG` 로 준다). 서버의 가짜 발송기(backend/app/phone_verification/sms.py FakeSmsSender)가 `runs_locally` 일 때만
`가짜 문자 발송(로컬) to=…<끝4자리> text=[CampusMate] 인증번호 [123456]…` 한 줄을 남기고, 이 모듈이 그 줄에서 6자리를 읽는다.

서버 한도: 같은 번호 60초에 1번 · 하루 5번 · 계정당 하루 10번, 인증한 번호는 활동 계정 하나에만 묶인다 → 가설마다 시작할 때
[reset] 으로 로컬 DB 의 인증 줄 · 묶임을 비운다(운영 DB 는 절대 아니다 — [require_local]).
"""

import os
import re
import threading
import time
import urllib.parse
from datetime import datetime, timedelta, timezone
from pathlib import Path

from e2e import tools
from e2e.tools import Blocked

PHONE_ENV = 'E2E_TEST_PHONE'
PHONE_FILE_ENV = 'E2E_TEST_PHONE_FILE'
LOG_KEY = 'E2E_SERVER_LOG'
# 서버가 같은 번호로 다시 보내게 하는 최소 간격(초) — 이보다 더 과거로 보낸 시각을 돌려놓는다.
COOLDOWN_BACK = timedelta(minutes=2)
POLL = 0.5  # 서버 로그를 다시 읽는 간격(초)
# 로그 줄: `… 가짜 문자 발송(로컬) to=…5432 text=[CampusMate] 인증번호 [123456]을 입력해 주세요.` 한글이 어떻게 읽혀도 되게 ASCII 만 본다.
_SMS_LINE = re.compile(r'to=\D{0,8}(\d{4}) text=\[CampusMate\][^\[\n]*\[(\d{6})\]')


def phone_file():
    """시험 번호 파일. 환경값 `E2E_TEST_PHONE_FILE` 로 바꿀 수 있고, 기본은 저장소 밖 비밀 폴더다."""
    return Path(os.environ[PHONE_FILE_ENV]) if os.environ.get(PHONE_FILE_ENV) else Path.home() / 'campusmate-secrets' / 'e2e-test-phone.txt'


def test_phone():
    """시험 번호 `010-xxxx-xxxx`. 환경값 `E2E_TEST_PHONE` 이 먼저, 없으면 파일. 못 읽으면 값을 적지 않고 [Blocked]."""
    raw = os.environ.get(PHONE_ENV)
    if raw is None:
        try:
            raw = phone_file().read_text(encoding='utf-8')
        except OSError:
            raise Blocked(f'시험 번호가 없다 — 환경값 {PHONE_ENV} 를 주거나 비밀 폴더의 e2e-test-phone.txt 에 시험 번호 하나를 적는다 '
                          '(무작위 번호로는 문자 인증 가설을 돌리지 않는다)') from None
    digits = re.sub(r'[\s-]', '', raw)
    if not re.fullmatch(r'010\d{8}', digits):
        raise Blocked(f'시험 번호 모양이 010 + 8자리가 아님 — {PHONE_ENV} 또는 e2e-test-phone.txt 를 고친다')
    return f'{digits[:3]}-{digits[3:7]}-{digits[7:]}'


def require_local(cfg):
    """운영 서버를 대상으로는 "인증번호 받기" 를 누르지 않는다 — 운영이면 [Blocked]. 두 군데를 다 본다:
    DB 주소(SUPABASE_URL 이 운영 `*.supabase.co` 가 아님)와 앱이 문자를 시키는 API 주소(API_BASE_URL 이 운영 Cloud Run `*.run.app` 이 아님).
    DB 만 로컬이고 API 가 운영이면 앱이 운영 서버로 번호를 보내 진짜 문자가 나간다. API_BASE_URL 이 없거나 비면 어디로 가는지 알 수 없으니 막는다
    (로컬 기본값은 없다 — e2e env 에 `API_BASE_URL=http://127.0.0.1:8000` 처럼 적는다)."""
    if not tools.is_local(cfg):
        raise Blocked('운영 서버를 대상으로는 인증번호 받기를 누르지 않는다(남의 폰에 문자가 갈 수 있다) — 로컬 스택에서만 돈다(E2E_ENV)')
    api = (cfg.get('API_BASE_URL') or '').strip()
    if not api:
        raise Blocked('API_BASE_URL 이 없거나 비어 앱이 문자를 시킬 서버를 알 수 없어 인증번호 받기를 누르지 않는다 — e2e env 에 로컬 서버 주소를 적는다')
    if (urllib.parse.urlsplit(api).hostname or '').endswith('.run.app'):
        raise Blocked('앱이 운영 서버(Cloud Run) API 주소를 향해 인증번호 받기를 누르지 않는다(남의 폰에 문자가 갈 수 있다) — API_BASE_URL 을 로컬 서버로 한다')


def server_log(cfg):
    """로컬 서버의 로그 파일. 환경값 `E2E_SERVER_LOG` 가 먼저, 없으면 e2e env 의 같은 키."""
    path = os.environ.get(LOG_KEY) or cfg.get(LOG_KEY)
    if not path:
        raise Blocked(f'로컬 서버 로그 파일을 모른다 — 서버를 `uvicorn app.main:app … > server.log 2>&1` 로 띄우고 그 파일을 {LOG_KEY} 로 준다')
    return Path(path)


def read_log(path):
    """로그 파일 전체 글. 없으면 빈 글. 윈도 PowerShell 의 리다이렉트(UTF-16)도 읽는다."""
    try:
        data = Path(path).read_bytes()
    except OSError:
        return ''
    if data.startswith((b'\xff\xfe', b'\xfe\xff')):
        return data.decode('utf-16', errors='replace')
    return data.decode('utf-8', errors='replace')


def codes_in(text, last4):
    """로그 글에서 끝 4자리가 [last4] 인 번호로 간 인증번호 6자리를 나온 순서대로."""
    return [code for tail, code in _SMS_LINE.findall(text) if tail == last4]


class CodeLog:
    """서버 로그에서 인증번호를 하나씩 꺼낸다. 만들 때 이미 있던 줄은 옛것이라 건너뛴다(앱을 켜기 전에 만든다)."""

    def __init__(self, path, last4, poll=None):
        self._path, self._last4, self._poll = Path(path), last4, poll
        self._lock = threading.Lock()
        self._seen = len(self._codes())

    def _codes(self):
        return codes_in(read_log(self._path), self._last4)

    def next_code(self, timeout=30):
        """아직 안 꺼낸 다음 인증번호. [timeout] 초 안에 로그에 안 나오면 [Blocked]."""
        deadline = time.monotonic() + timeout
        with self._lock:
            while True:
                codes = self._codes()
                if len(codes) < self._seen:  # 로그를 비웠거나 새로 시작했다
                    self._seen = 0
                if len(codes) > self._seen:
                    self._seen += 1
                    return codes[self._seen - 1]
                if time.monotonic() >= deadline:
                    raise Blocked(f'서버 로그({self._path.name})에 인증번호가 안 나옴 — 로컬 서버가 {LOG_KEY} 파일로 로그를 남기는지, '
                                  'SMS_PROVIDER 가 fake 인지, 앱의 인증번호 받기가 눌렸는지 본다')
                time.sleep(self._poll or POLL)


def reset(run):
    """로컬 DB 의 문자 인증 줄과 "인증한 번호" 묶임을 비운다 — 같은 시험 번호로 다음 가설이 다시 받을 수 있게(한도 · 묶임 풀기)."""
    require_local(run.cfg)
    _check('인증 줄 비우기', tools.rest(run.cfg, run.key, 'DELETE', 'phone_verifications?id=not.is.null'))
    _check('인증한 번호 묶임 풀기', tools.rest(run.cfg, run.key, 'PATCH', 'profile_private?phone_verified_at=not.is.null',
                                              {'phone_verified_at': None}))


def release_cooldown(run):
    """보낸 줄의 시각을 2분 뒤로 돌려 "같은 번호 60초에 1번" 을 풀어 준다 — 인증은 그대로 둔다(두 기기가 차례로 받을 때)."""
    require_local(run.cfg)
    back = (datetime.now(timezone.utc) - COOLDOWN_BACK).isoformat()
    _check('받기 간격 풀기', tools.rest(run.cfg, run.key, 'PATCH', 'phone_verifications?code_hash=not.is.null', {'sent_at': back}))


def _check(what, reply):
    status, body = reply
    if status >= 300:
        raise Blocked(f'{what} {status} — 로컬 DB 에 문자 인증 마이그레이션(20261111010000)이 적용됐는지 본다 {str(body)[:120]}')


def stepping(hub, *handlers):
    """앱이 `step` 을 말하고 멈출 때마다 [handlers] 를 차례로 부르는 midway(Run.phone 에 넘긴다). 핸들러가 돌려준 dict 는 다음 go 에
    실려 앱의 `step` 이 받는다(인증번호). 마지막 핸들러의 값은 Run.phone 이 마지막 go 로 보낸다."""
    def midway(first):
        extra = handlers[0](first)
        for number, handler in enumerate(handlers[1:], start=2):
            hub.go(extra if isinstance(extra, dict) else None)
            said = hub.wait(120)
            if said is None or 'result' in said:
                raise Blocked(f'앱이 {number}번째 멈춤 전에 {"끝남" if said else "답하지 않음"}')
            extra = handler(said)
        return extra
    return midway


class SendTurn:
    """한 번에 한 기기만 인증번호를 받게 줄 세운다 — 같은 번호는 60초에 1번이라 두 기기가 동시에 누르면 한쪽이 막힌다.
    [take] 로 차례를 받으며 앞 기기가 받은 줄의 간격을 풀고, 그 기기가 인증을 마치면 [give_back] 으로 넘긴다."""

    def __init__(self, run, wait=120):
        self._run, self._wait = run, wait
        self._lock = threading.Lock()
        self._owner = None

    def take(self, who):
        if not self._lock.acquire(timeout=self._wait):
            raise Blocked('짝 기기가 인증을 끝내지 않아 인증번호 받기 차례가 안 옴')
        self._owner = who
        try:
            release_cooldown(self._run)
        except BaseException:
            self.give_back(who)
            raise

    def give_back(self, who):
        if self._owner == who:
            self._owner = None
            self._lock.release()
