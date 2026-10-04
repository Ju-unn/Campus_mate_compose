"""E2E 진행 프로그램의 연장 — 우편함 · adb · 설정 · Supabase/FastAPI 호출 · 결과 기록. 표준 라이브러리만 쓴다.

비밀값(서비스 키)은 [service_key] 로 그때그때 받아 메모리에만 둔다 — 파일 · 결과 · 로그에 적지 않는다.
"""

import json
import queue
import random
import re
import string
import subprocess
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ENV_FILE = ROOT / 'frontend' / 'e2e.env'
PACKAGE = 'io.github.juunn.campusmate'
# 자식 프로세스 출력은 UTF-8 로 읽는다 — 윈도 기본(cp949)으로 읽으면 dumpsys 의 한글에서 UnicodeDecodeError 로 stdout 이 None 이 된다.
TEXT = dict(capture_output=True, text=True, encoding='utf-8', errors='replace')
DEVICE_PORT = 8765  # 기기 쪽은 늘 이 포트 — PC 쪽 포트는 adb reverse 로 기기마다 가른다.
# 기기 이름 → PC 쪽 포트. 실폰 시리얼은 공개 저장소에 두지 않고 e2e.env 의 E2E_DEVICE_A 에서 읽는다.
DEVICES = {'A': 8765, 'B': 8766}
DEFAULT_SERIALS = {'B': 'emulator-5554'}


class Hub:
    """PC 우편함. 진행이 [tell] 로 넣은 일감을 앱이 GET /hear 로 가져가고, 앱이 POST /say 로 보낸 것을 진행이 [wait] 로 받는다."""

    def __init__(self, port):
        self._jobs = queue.Queue()
        self._said = queue.Queue()
        hub = self

        class Handler(BaseHTTPRequestHandler):
            def do_GET(self):
                url = urllib.parse.urlsplit(self.path)
                if url.path != '/hear':
                    return self.send_error(404)
                # 긴 폴링 — 기다리는 동안 일감이 오면 바로 준다. 앱은 204 면 다시 묻는다.
                # ponytail: 꺼진 앱의 늦은 /hear 가 다음 일감을 가로챌 수 있다 — 5초로 창을 좁혔다. 실제로 생기면 일감에 시도 번호를 붙여 앱이 확인.
                wait = float(urllib.parse.parse_qs(url.query).get('wait', ['5'])[0])
                try:
                    job = hub._jobs.get(timeout=wait) if wait > 0 else hub._jobs.get_nowait()
                except queue.Empty:
                    self.send_response(204)
                    return self.end_headers()
                body = json.dumps(job).encode()
                self.send_response(200)
                self.send_header('Content-Type', 'application/json')
                self.send_header('Content-Length', str(len(body)))
                self.end_headers()
                self.wfile.write(body)

            def do_POST(self):
                if self.path != '/say':
                    return self.send_error(404)
                hub._said.put(json.loads(self.rfile.read(int(self.headers['Content-Length']))))
                self.send_response(204)
                self.end_headers()

            def log_message(self, *args):
                pass

        self._server = ThreadingHTTPServer(('127.0.0.1', port), Handler)
        self.port = self._server.server_address[1]
        threading.Thread(target=self._server.serve_forever, daemon=True).start()

    def tell(self, job):
        """새 일감 하나만 남긴다 — 앞 시도에서 앱이 못 가져간 일감 · 늦게 온 말이 다음 시도에 섞이지 않게."""
        for q in (self._jobs, self._said):
            while not q.empty():
                q.get_nowait()
        self._jobs.put(job)

    def go(self):
        """중간에 멈춘 앱을 다시 보낸다 — [tell] 과 달리 남은 말을 지우지 않는다."""
        self._jobs.put({'go': True})

    def wait(self, timeout):
        """앱이 보낸 다음 말. [timeout] 초 안에 없으면 None."""
        try:
            return self._said.get(timeout=timeout)
        except queue.Empty:
            return None

    def result(self, timeout):
        """`result` 가 든 말이 올 때까지 — 중간 값(로그인 됨 등)은 건너뛴다. [timeout] 초 안에 없으면 None."""
        deadline = time.monotonic() + timeout
        while (said := self.wait(max(0, deadline - time.monotonic()))) is not None:
            if 'result' in said:
                return said
        return None

    def close(self):
        self._server.shutdown()
        self._server.server_close()


def env(path=ENV_FILE):
    """`frontend/e2e.env`(gitignore) — 빌드의 --dart-define-from-file 과 같은 파일을 진행도 읽는다."""
    if not Path(path).exists():
        raise SystemExit(f'{path} 가 없다 — SUPABASE_URL · SUPABASE_ANON_KEY · API_BASE_URL · E2E_MAIL_BASE · E2E_DEVICE_A 를 적는다.')
    pairs = {}
    for line in Path(path).read_text(encoding='utf-8').splitlines():
        line = line.strip()
        if line and not line.startswith('#') and '=' in line:
            key, value = line.split('=', 1)
            pairs[key.strip()] = value.strip()
    return pairs


def serial(name, cfg):
    """기기 이름(A · B) → adb 시리얼."""
    return cfg.get(f'E2E_DEVICE_{name}') or DEFAULT_SERIALS.get(name)


def adb(serial, *args, check=True):
    return subprocess.run(['adb', '-s', serial, *args], **TEXT, check=check).stdout


def screencap(serial):
    """기기 화면 한 장(PNG 바이트)."""
    return subprocess.run(['adb', '-s', serial, 'exec-out', 'screencap', '-p'], capture_output=True, check=True).stdout


def service_key():
    """서비스 키를 Secret Manager 에서 받아 돌려준다 — 메모리에만 둔다."""
    return subprocess.run(
        ['gcloud', 'secrets', 'versions', 'access', 'latest', '--secret=supabase-service-role-key'],
        **TEXT, check=True, shell=True,  # 윈도는 gcloud 가 .cmd 라 shell 로 부른다
    ).stdout.strip()


class Reply(tuple):
    """(상태 코드, 본문) — 둘로 풀어 쓰고, 응답 헤더는 [headers](소문자 키)로 본다(X-Account-Status 같은 가설)."""

    def __new__(cls, status, body, headers=None):
        reply = super().__new__(cls, (status, body))
        reply.headers = {k.lower(): v for k, v in (headers or {}).items()}
        return reply

    status = property(lambda self: self[0])
    body = property(lambda self: self[1])


def call(method, url, headers=None, body=None, raw=None):
    """요청 하나 → [Reply]. 본문 JSON · JSON 아니면 글자 · 없으면 None — 4xx · 5xx 도 예외 없이 돌려준다(가설이 상태 코드를 본다).
    [raw] = (바이트, Content-Type) 면 JSON 대신 그대로 보낸다(학생증 multipart)."""
    data, kind = raw if raw else (None if body is None else json.dumps(body).encode(), 'application/json')
    req = urllib.request.Request(url, data=data, method=method, headers={'Content-Type': kind, **(headers or {})})
    try:
        with urllib.request.urlopen(req, timeout=30) as res:
            status, got, head = res.status, res.read(), res.headers
    except urllib.error.HTTPError as e:
        status, got, head = e.code, e.read(), e.headers
    head = dict(head.items()) if head else {}
    if not got:
        return Reply(status, None, head)
    try:
        return Reply(status, json.loads(got), head)
    except ValueError:
        return Reply(status, got.decode(errors='replace'), head)


def rest(cfg, key, method, path, body=None, token=None):
    """Supabase REST(`/rest/v1/...`). 서비스 키로 읽고 쓰거나, [key]=anon 키 + [token]=사용자 access_token 으로 RLS 를 거친다."""
    return call(method, f"{cfg['SUPABASE_URL']}/rest/v1/{path}", {'apikey': key, 'Authorization': f'Bearer {token or key}'}, body)


def admin(cfg, key, method, path, body=None):
    """Supabase Auth 관리자(`/auth/v1/admin/...`) — generate_link · 사용자 삭제. 서비스 키로만."""
    return call(method, f"{cfg['SUPABASE_URL']}/auth/v1/admin/{path}", {'apikey': key, 'Authorization': f'Bearer {key}'}, body)


def api(cfg, method, path, token, body=None):
    """FastAPI(API_BASE_URL) — 사용자 access_token 으로."""
    return call(method, f"{cfg['API_BASE_URL']}{path}", {'Authorization': f'Bearer {token}'}, body)


class Blocked(Exception):
    """가설 준비(계정 만들기 등)가 안 됨 — 결과는 fail 이 아니라 blocked."""


# 뒷정리가 비우는 버킷 — 사용자 파일은 모두 `{id}/` 아래다.
BUCKETS = ('avatars', 'profile-photos', 'student-id-temp', 'heart-task-proofs')
BLOCKS_SNAPSHOT = 'signup_blocks_시작.json'  # E2E_결과/ 안 — 이 밖의 재가입 제한만 시험이 만든 것이다
KEEP_FILE = 'KEEP.txt'  # E2E_결과/ 안 — 적힌 id 는 무슨 일이 있어도 지우지 않는다
# 계정 단계 = "여기까지 끝냈다". basic 뒤는 서버 온보딩 순서(onboarding_progress._STEPS) 그대로, home = bio 까지.
STAGES = ('new', 'consented', 'pending', 'verified', 'gate_done', 'basic', 'kakao', 'photos', 'appearance', 'interests',
          'my_traits', 'survey', 'avatar', 'ideal_conditions', 'ideal_traits', 'ideal_note', 'home')
OLD_CONSENT_VERSION = '2026-09-01'  # 서버 상수(consents/policy.py)보다 옛 판 — 재동의 가설이 데이터로 흉내 낸다
PHOTO = ROOT / 'frontend' / 'assets' / 'images' / 'mascot-male.png'  # 실제 사람 사진 대신 앱에 든 그림(SafeSearch 통과)


def mail_base(cfg):
    """E2E_MAIL_BASE(`이름@도메인`) → (이름, 도메인). 시험 계정은 `이름+e2e번호@도메인`."""
    local, _, domain = cfg['E2E_MAIL_BASE'].partition('@')
    return local, domain or 'gmail.com'


def e2e_pattern(cfg):
    """뒷정리 대상 — 이 정규식에 맞는 주소만 지운다."""
    local, domain = mail_base(cfg)
    return re.compile(rf'^{re.escape(local)}\+e2e\d+@{re.escape(domain)}$')


def keep_ids(text):
    return set(re.findall(r'[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}', text))


def keep(root):
    path = Path(root) / KEEP_FILE
    if not path.exists():
        raise SystemExit(f'{path} 가 없다 — 지우면 안 되는 계정을 모르면 지우지 않는다.')
    return keep_ids(path.read_text(encoding='utf-8'))


def auth_users(cfg, key):
    users, page = [], 1
    while True:
        status, body = admin(cfg, key, 'GET', f'users?page={page}&per_page=1000')
        if status != 200:
            raise SystemExit(f'사용자 목록을 못 읽었다({status})')
        users += body['users']
        if len(body['users']) < 1000:
            return users
        page += 1


def real_users(users, pattern, keep):
    """시험 계정(`+e2e` 별칭)도 KEEP 도 아닌 사용자 — 하나라도 있으면 운영 쓰기를 하지 않는다."""
    return [u for u in users if u['id'] not in keep and not pattern.match((u.get('email') or '').lower())]


def ensure_no_real_users(cfg, key, root):
    """운영 쓰기 · 지우기 전마다 — 실사용자가 하나라도 보이면 멈춘다(설계 2절 안전). 통과하면 0."""
    real = real_users(auth_users(cfg, key), e2e_pattern(cfg), keep(root))
    if real:
        raise SystemExit(f'실사용자 {len(real)}명이 보인다 — 멈춘다')
    return 0


def _service(cfg, key, method, path, body=None):
    return call(method, f"{cfg['SUPABASE_URL']}{path}", {'apikey': key, 'Authorization': f'Bearer {key}'}, body)


def storage_paths(cfg, key, bucket, prefix):
    """버킷 안 [prefix] 아래 파일 경로 전부(폴더는 따라 들어간다)."""
    status, items = _service(cfg, key, 'POST', f'/storage/v1/object/list/{bucket}', {'prefix': prefix, 'limit': 1000})
    if status != 200:
        raise SystemExit(f'{bucket}/{prefix} 목록을 못 읽었다({status})')
    for item in items:
        path = f"{prefix}/{item['name']}"
        if item.get('id') is None:
            yield from storage_paths(cfg, key, bucket, path)
        else:
            yield path


def delete_user(cfg, key, uid, keep):
    """버킷 4개의 `{id}/` 와 그 계정이 넣었거나 받은 신고를 지우고 관리자 삭제(프로필 이하는 cascade). KEEP 은 여기서 한 번 더 막는다."""
    if uid in keep:
        raise SystemExit(f'{uid} 는 KEEP 이다 — 지우지 않는다')
    for bucket in BUCKETS:
        paths = list(storage_paths(cfg, key, bucket, uid))
        if paths:
            status, body = _service(cfg, key, 'DELETE', f'/storage/v1/object/{bucket}', {'prefixes': paths})
            if status >= 300:  # 파일을 남긴 채 계정을 지우면 `{id}/` 가 고아가 된다
                raise SystemExit(f'{bucket}/{uid}/ 비우기 실패({status}) {body}')
    # 그 계정이 넣었거나 받은 신고 — 계정을 지우면 두 칸이 비어(on delete set null) 주인 없는 열린 신고로 남는다.
    status, body = rest(cfg, key, 'DELETE', f'reports?or=(reporter_id.eq.{uid},target_profile_id.eq.{uid})')
    if status >= 300:
        raise SystemExit(f'{uid} 의 신고 지우기 실패({status}) {body}')
    status, body = admin(cfg, key, 'DELETE', f'users/{uid}')
    if status >= 300:
        raise SystemExit(f'{uid} 삭제 실패({status}) {body}')


def snapshot_blocks(cfg, key, root):
    """처음 한 번만 — 그 뒤에 생긴 signup_blocks 행이 시험이 만든 것이다."""
    path = Path(root) / BLOCKS_SNAPSHOT
    if path.exists():
        return
    status, rows = rest(cfg, key, 'GET', 'signup_blocks?select=email_hmac')
    if status != 200:
        raise SystemExit(f'signup_blocks 를 못 읽었다({status})')
    path.write_text(json.dumps([r['email_hmac'] for r in rows]), encoding='utf-8')


def cleanup(cfg, key, root):
    """`+e2e` 계정 · 파일 · 시험이 만든 재가입 제한을 지운다. 실사용자가 보이면 아무것도 건드리지 않고 멈춘다."""
    kept, pattern = keep(root), e2e_pattern(cfg)
    ensure_no_real_users(cfg, key, root)
    for user in auth_users(cfg, key):
        if user['id'] not in kept and pattern.match(user['email'].lower()):
            delete_user(cfg, key, user['id'], kept)
            print(f"지움 {user['email']}")
    snapshot = Path(root) / BLOCKS_SNAPSHOT
    if not snapshot.exists():
        print(f'{snapshot.name} 가 없어 signup_blocks 는 건드리지 않았다')
        return
    start = set(json.loads(snapshot.read_text(encoding='utf-8')))
    status, rows = rest(cfg, key, 'GET', 'signup_blocks?select=email_hmac')
    if status != 200:
        raise SystemExit(f'signup_blocks 를 못 읽었다({status})')
    for row in rows:
        if row['email_hmac'] not in start:
            rest(cfg, key, 'DELETE', f"signup_blocks?email_hmac=eq.{urllib.parse.quote(row['email_hmac'])}")
            print('재가입 제한 1행 지움')


def form(url, token, fields, file):
    """multipart 한 번 — [file] = (칸 이름, 파일 이름, 바이트, Content-Type)."""
    boundary = uuid.uuid4().hex
    parts = [f'--{boundary}\r\nContent-Disposition: form-data; name="{k}"\r\n\r\n{v}\r\n'.encode() for k, v in fields.items()]
    name, filename, data, kind = file
    parts.append(f'--{boundary}\r\nContent-Disposition: form-data; name="{name}"; filename="{filename}"\r\n'
                 f'Content-Type: {kind}\r\n\r\n'.encode() + data + f'\r\n--{boundary}--\r\n'.encode())
    return call('POST', url, {'Authorization': f'Bearer {token}'}, raw=(b''.join(parts), f'multipart/form-data; boundary={boundary}'))


def batch(name):
    """Cloud Scheduler job `campus-mate-<name>` 을 지금 한 번 돌린다(정리 배치 = cleanup). 끝을 기다리지 않는다 —
    가설이 DB 를 다시 읽어 결과가 보일 때까지 기다린다.
    ponytail: gcloud 를 그대로 부른다(DEPLOY.md §정리 배치 "확인"). 스케줄러 SA ID 토큰으로 /batch/* 를 직접 부르는 길로
    바꾸려면 이 함수만 바꾸면 된다(tokenCreator 부여 · 회수가 따라온다)."""
    subprocess.run(['gcloud', 'scheduler', 'jobs', 'run', f'campus-mate-{name}', '--location=asia-northeast3'],
                   **TEXT, check=True, shell=True)  # 윈도는 gcloud 가 .cmd 라 shell 로 부른다


def basic_info():
    """04-1 기본 정보 — 닉네임은 영문 5자 무작위(중복 금지), 번호도 무작위."""
    return {'nickname': ''.join(random.choices(string.ascii_letters, k=5)), 'birth_year': datetime.now().year - 22,
            'height_cm': 170, 'phone_number': f'010-{random.randint(0, 9999):04d}-{random.randint(0, 9999):04d}',
            'gender': 'male', 'mbti': None}


def verdict(said):
    """앱이 한 말 → (결과, 메모). 말이 없었으면 시간 초과 fail."""
    if said is None:
        return 'fail', '앱이 시간 안에 답하지 않음'
    return said['result'], said.get('note', '')


def latest(records):
    """가설마다 마지막 줄 — 재실행이 앞 결과를 덮는다."""
    return {r['case']: r for r in records}


def scenario_rows(md):
    """시나리오 md 의 가설 표 줄(`| E-… |`)만. 칸: 번호 · 가설 · 기기 · 준비 · 누르는 것 · 통과 조건 · 방식 · 근거."""
    rows = []
    for line in md.splitlines():
        # ponytail: 칸 안에 '|' 가 있으면 칸이 밀린다 — 앞 세 칸과 방식만 쓰므로, 생기면 그때 백틱 안 '|' 를 건너뛰게.
        cells = [c.strip() for c in line.strip().strip('|').split('|')]
        if re.fullmatch(r'E-[A-Z]+-\d+', cells[0]) and len(cells) >= 8:
            rows.append({'case': cells[0], 'hypothesis': cells[1], 'device': cells[2], 'method': cells[6]})
    return rows


class Run:
    """한 묶음 실행 — 결과는 `<out>/results.jsonl` 한 줄씩(pass · fail · blocked · known · skip)."""

    def __init__(self, out, build, revision=None, cfg=None, key=None):
        self.out = Path(out)
        self.out.mkdir(parents=True, exist_ok=True)
        self.build = build
        self.revision = revision
        self.cfg = cfg  # e2e.env — API 가설 · 계정 공장
        self.key = key  # 서비스 키 — 메모리에만

    def alias(self, domain=None):
        """처음 쓰는 별칭 `이름+e2e번호@도메인`. 번호표는 E2E_결과/ 에 하나 — 묶음이 달라도 번호를 다시 쓰지 않는다."""
        ticket = self.out.parent / '별칭_번호표.txt'
        n = int(ticket.read_text(encoding='utf-8')) if ticket.exists() else 1001
        ticket.write_text(str(n + 1), encoding='utf-8')  # 쓰기 전에 넘긴다 — 실패한 번호도 다시 안 쓴다
        local, base = mail_base(self.cfg)
        return n, f'{local}+e2e{n}@{domain or base}'

    def remember(self, account):
        """accounts.json — 만든 즉시 적고 단계가 오를 때마다 고친다. 토큰은 적지 않는다."""
        path = self.out / 'accounts.json'
        accounts = json.loads(path.read_text(encoding='utf-8')) if path.exists() else []
        accounts = [a for a in accounts if a['n'] != account['n']] + [{k: account[k] for k in ('n', 'email', 'id', 'stage', 'at')}]
        path.write_text(json.dumps(accounts, ensure_ascii=False, indent=1), encoding='utf-8')

    def account(self, stage, old_consent=False, **basic):
        """새 시험 계정을 [stage] 까지 올려 {n, email, id, stage, at, token} 으로. 어느 단계든 안 되면 [Blocked].
        [old_consent] 면 동의를 옛 판 행으로 넣는다(재동의 가설 — 온보딩 API 는 동의 판을 안 본다, next-step 만 본다).
        [basic] 은 04-1 값을 정해 넣는다(같은 전화번호 가설)."""
        if stage not in STAGES:
            raise ValueError(f'{stage} — 계정 단계는 {STAGES}')
        n, email = self.alias()
        status, body = admin(self.cfg, self.key, 'POST', 'users', {'email': email, 'email_confirm': True})
        if status != 200:
            raise Blocked(f'계정 만들기 {status} {body}')
        account = {'n': n, 'email': email, 'id': body['id'], 'stage': 'new',
                   'at': datetime.now(timezone.utc).isoformat(timespec='seconds')}
        self.remember(account)
        token = self.sign_in(email)
        steps = ['consented', 'pending'] if stage == 'pending' else [s for s in STAGES[1:] if s != 'pending']
        for step in steps[:steps.index(stage) + 1] if stage != 'new' else []:
            if step == 'consented' and old_consent:
                self._old_consent(account)
            else:
                self._step(step, account, token, basic)
            account['stage'] = step
            self.remember(account)
        return {**account, 'token': token}

    def link(self, email):
        """관리자 generate_link 의 1회용 토큰(token_hash) — 메일이 나가지 않는다. 폰 가설은 이것을 앱에 넘긴다."""
        status, body = admin(self.cfg, self.key, 'POST', 'generate_link', {'type': 'magiclink', 'email': email})
        hashed = (body or {}).get('hashed_token') or (body or {}).get('properties', {}).get('hashed_token')
        if status != 200 or not hashed:
            raise Blocked(f'generate_link {status}')
        return hashed

    def sign_in(self, email):
        """[link] 로 받은 1회용 토큰으로 PC 쪽 로그인."""
        status, body = call('POST', f"{self.cfg['SUPABASE_URL']}/auth/v1/verify", {'apikey': self.cfg['SUPABASE_ANON_KEY']},
                            {'type': 'magiclink', 'token_hash': self.link(email)})
        if status != 200:
            raise Blocked(f'verify {status}')
        return body['access_token']

    def _old_consent(self, account):
        """user_consents 는 고치지 않는 기록이라 서비스 키도 update 권한이 없다 — 옛 판 행을 처음부터 넣는다."""
        reply = rest(self.cfg, self.key, 'POST', 'user_consents',
                     [{'profile_id': account['id'], 'kind': k, 'version': OLD_CONSENT_VERSION} for k in ('privacy', 'terms')])
        if reply[0] >= 300:
            raise Blocked(f'옛 판 동의 {reply[0]} {reply[1]}')

    def _photos(self, account, token):
        url = f"{self.cfg['API_BASE_URL']}/profile-onboarding/photos"
        data = PHOTO.read_bytes()
        for position in (0, 1):
            fields = {'position': position, 'is_avatar_source': 'true' if position == 0 else 'false'}
            reply = form(url, token, fields, ('photo', f'e2e{position}.png', data, 'image/png'))
            if reply[0] >= 300:
                return reply
        return reply

    def _avatar(self, account, status='ready'):
        """아바타는 AI 대신 DB 완성 행(계획 확인 9) — 그림은 avatars 버킷 `{id}/` 에 올려 뒷정리가 같이 지운다."""
        path = f"{account['id']}/e2e-{uuid.uuid4().hex}.png"
        uploaded = call('POST', f"{self.cfg['SUPABASE_URL']}/storage/v1/object/avatars/{path}",
                        {'apikey': self.key, 'Authorization': f'Bearer {self.key}'}, raw=(PHOTO.read_bytes(), 'image/png'))
        if uploaded[0] >= 300:
            return uploaded
        return rest(self.cfg, self.key, 'POST', 'profile_avatars',
                    {'profile_id': account['id'], 'storage_path': path, 'status': status})

    def _step(self, step, account, token, basic=None):
        on = lambda path, body: api(self.cfg, 'POST', f'/profile-onboarding/{path}', token, body)
        if step == 'consented':
            reply = api(self.cfg, 'POST', '/me/consents', token, {'agreed': ['terms', 'privacy']})
        elif step in ('pending', 'verified'):  # 검토는 사람이 하는 일이라 DB 로 바로 둔다
            reply = rest(self.cfg, self.key, 'PATCH', f"profiles?id=eq.{account['id']}", {'student_verification': step})
        elif step == 'gate_done':
            reply = api(self.cfg, 'POST', '/school-info', token, {'department': '컴퓨터공학과', 'student_number': f"e2e{account['n']}"})
        elif step == 'basic':
            reply = on('basic-info', {**basic_info(), **(basic or {})})
        elif step == 'kakao':
            reply = on('kakao-id', {'kakao_id': f"e2e{account['n']}"})
        elif step == 'photos':
            reply = self._photos(account, token)
        elif step == 'appearance':
            reply = on('appearance-type', {'animal_type': 'dog', 'impression_type': 'kind'})
        elif step == 'interests':
            reply = on('interests', {'tags': ['카페가기', '자전거', '패션']})
        elif step == 'my_traits':
            reply = on('my-traits', {'tags': ['깨끗한 피부', '좋은 비율', '달달한 목소리']})
        elif step == 'survey':
            reply = on('survey', {'answers': {str(axis): 0.5 for axis in range(1, 10)}, 'religion': 'none', 'is_smoker': False})
        elif step == 'avatar':
            reply = self._avatar(account)
        elif step == 'ideal_conditions':
            reply = on('ideal-conditions', {'preferred_age_min': 20, 'preferred_age_max': 30,
                                            'preferred_animal_types': ['dog'], 'preferred_impression_types': ['kind']})
        elif step == 'ideal_traits':
            reply = on('ideal-traits', {'tags': ['연상', '연하', '동갑']})
        elif step == 'ideal_note':
            reply = on('ideal-note', {'note': '대화가 잘 통하는 사람이면 좋겠어요'})
        else:
            reply = on('bio', {'bio': '주말엔 카페에서 책을 읽어요.'})
        if reply[0] >= 300:
            raise Blocked(f'{step} {reply[0]} {reply[1]}')

    def shot(self, serial, case):
        """실패한 가설의 화면 한 장을 `<out>/shots/<번호>.png` 로 — 개인정보가 있을 수 있어 PC 에만 둔다. 못 찍어도 판정은 그대로."""
        try:
            path = self.out / 'shots' / f'{case}.png'
            path.parent.mkdir(exist_ok=True)
            path.write_bytes(screencap(serial))
            return path
        except Exception:
            return None

    @property
    def results(self):
        return self.out / 'results.jsonl'

    def record(self, case, result, note=''):
        line = {'case': case, 'result': result, 'note': note, 'build': self.build, 'revision': self.revision,
                'at': datetime.now(timezone.utc).isoformat(timespec='seconds')}
        with self.results.open('a', encoding='utf-8') as f:
            f.write(json.dumps(line, ensure_ascii=False) + '\n')
        return line

    def records(self):
        if not self.results.exists():
            return []
        return [json.loads(l) for l in self.results.read_text(encoding='utf-8').splitlines() if l.strip()]

    def phone(self, hub, serial, job, timeout=180, midway=None):
        """앱을 새로 켜서 가설 하나. 앱이 말한 결과(dict)를, 시간 안에 말이 없으면 None.

        [midway] 가 있으면 앱이 `step` 을 말하고 멈춘 사이에 PC 가 그것을 부르고({'go': True} 로 앱을 다시 보낸다)
        — 홈에 있는 동안 정지를 거는 가설(E-GATE-04)처럼 앱 실행 중간에 서버 상태를 바꿀 때.

        앞 프로세스를 `run-as … kill -9` 로 끝낸다(debug 빌드라 된다). `am kill` 은 방금 HOME 으로 내린 "직전 앱"
        (oom adj 700)을 죽이지 않아 monkey 가 옛 프로세스를 꺼내기만 하고 main 이 다시 안 돈다(10-04 실폰 확인).
        force-stop 은 앱을 stopped 상태로 만들어 FCM 을 멈추므로 쓰지 않는다 — kill -9 는 OS 가 메모리로 죽인 것과 같다.
        """
        adb(serial, 'shell', 'input', 'keyevent', 'KEYCODE_HOME')
        for _ in range(10):
            pid = adb(serial, 'shell', 'pidof', PACKAGE, check=False).strip()
            if not pid:
                break
            adb(serial, 'shell', 'run-as', PACKAGE, 'kill', '-9', pid, check=False)
            time.sleep(0.5)
        else:
            return {'case': job['case'], 'result': 'blocked', 'note': '앞 앱 프로세스가 꺼지지 않음(debug 빌드인가 — run-as 는 debug 만 된다)'}
        adb(serial, 'shell', 'monkey', '-p', PACKAGE, '-c', 'android.intent.category.LAUNCHER', '1')
        hub.tell(job)
        if midway:
            said = hub.wait(timeout)
            if said is None or 'result' in said:  # 멈추기 전에 끝났으면(실패 등) 그대로 돌려준다
                return said
            midway(said)
            hub.go()
        return hub.result(timeout)
