"""E2E 진행 프로그램의 연장 — 우편함 · adb · 설정 · Supabase/FastAPI 호출 · 결과 기록. 표준 라이브러리만 쓴다.

비밀값(서비스 키)은 [service_key] 로 그때그때 받아 메모리에만 둔다 — 파일 · 결과 · 로그에 적지 않는다.
"""

import json
import queue
import re
import subprocess
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ENV_FILE = ROOT / 'frontend' / 'e2e.env'
PACKAGE = 'io.github.juunn.campusmate'
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
    return subprocess.run(['adb', '-s', serial, *args], capture_output=True, text=True, check=check).stdout


def service_key():
    """서비스 키를 Secret Manager 에서 받아 돌려준다 — 메모리에만 둔다."""
    return subprocess.run(
        ['gcloud', 'secrets', 'versions', 'access', 'latest', '--secret=supabase-service-role-key'],
        capture_output=True, text=True, check=True, shell=True,  # 윈도는 gcloud 가 .cmd 라 shell 로 부른다
    ).stdout.strip()


def call(method, url, headers=None, body=None):
    """JSON 요청 하나. (상태 코드, 본문 JSON · JSON 아니면 글자 · 없으면 None) — 4xx · 5xx 도 예외 없이 돌려준다(가설이 상태 코드를 본다)."""
    data = None if body is None else json.dumps(body).encode()
    req = urllib.request.Request(url, data=data, method=method, headers={'Content-Type': 'application/json', **(headers or {})})
    try:
        with urllib.request.urlopen(req, timeout=30) as res:
            status, raw = res.status, res.read()
    except urllib.error.HTTPError as e:
        status, raw = e.code, e.read()
    if not raw:
        return status, None
    try:
        return status, json.loads(raw)
    except ValueError:
        return status, raw.decode(errors='replace')


def rest(cfg, key, method, path, body=None, token=None):
    """Supabase REST(`/rest/v1/...`). 서비스 키로 읽고 쓰거나, [key]=anon 키 + [token]=사용자 access_token 으로 RLS 를 거친다."""
    return call(method, f"{cfg['SUPABASE_URL']}/rest/v1/{path}", {'apikey': key, 'Authorization': f'Bearer {token or key}'}, body)


def admin(cfg, key, method, path, body=None):
    """Supabase Auth 관리자(`/auth/v1/admin/...`) — generate_link · 사용자 삭제. 서비스 키로만."""
    return call(method, f"{cfg['SUPABASE_URL']}/auth/v1/admin/{path}", {'apikey': key, 'Authorization': f'Bearer {key}'}, body)


def api(cfg, method, path, token, body=None):
    """FastAPI(API_BASE_URL) — 사용자 access_token 으로."""
    return call(method, f"{cfg['API_BASE_URL']}{path}", {'Authorization': f'Bearer {token}'}, body)


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

    def __init__(self, out, build, revision=None):
        self.out = Path(out)
        self.out.mkdir(parents=True, exist_ok=True)
        self.build = build
        self.revision = revision

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

    def phone(self, hub, serial, job, timeout=180):
        """앱을 새로 켜서 가설 하나. 앱이 말한 결과(dict)를, 시간 안에 말이 없으면 None.

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
        return hub.result(timeout)
