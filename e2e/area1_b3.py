"""영역 1 묶음 3 — 사진 세트(학생증 제출 · 04-2 사진 고르기 · 사진 API 경계).
기대값은 바탕화면 E2E_최종테스트_시나리오.md 영역 1 의 그 줄이다. 앱 쪽은 frontend/integration_test/area1_b3.dart 의 같은 번호.

사진 파일은 저장소에 없다 — 바탕화면 E2E_결과/사진/ 에 대장이 둔다(`python -m e2e photos` 가 빠진 이름을 알려 준다).
가설을 돌릴 때 필요한 파일만 폰 앱 캐시(`cache/e2e-photos/`)로 옮기고, 앱이 그 파일로 갤러리 훅을 갈아끼운다.
폰 가설은 area1.PHONE, API 가설은 area1.CASES 에 더해 `python -m e2e run area1-b3` 한 번으로 돈다.
"""

from datetime import datetime, timezone

from e2e import area1, tools
from e2e.area1 import Check, _app, _form, _one, _patch, _rows
from e2e.tools import Blocked

PHOTO_SET = ('face1.jpg', 'face2.jpg', 'face3.jpg', 'face4.jpg', 'scenery.jpg', 'id_ok.jpg', 'id_name.jpg', 'id_school.jpg',
             'id_blank.jpg', 'cert_noface.jpg', 'unsafe.jpg')
REAL_NAME = '홍길동'  # id_ok.jpg 에 그려 넣은 이름. id_name.jpg 는 다른 이름이라 같은 실명으로 내면 불일치가 된다.
REJECT_REASON = '사진이 흐려요'
PHOTO_UNREADABLE = '사진을 다시 확인해 주세요'
REMOTE = '/data/local/tmp/e2e-photos'  # adb push 는 앱 폴더에 못 쓴다 — 여기 두었다가 run-as 로 앱 캐시에 옮긴다
APP_DIR = 'cache/e2e-photos'  # 앱의 getTemporaryDirectory()/e2e-photos

# 시나리오에 있지만 이 묶음에 안 넣은 것.
LEFT_OUT = {
    'E-GATE-30': '묶음 1 폰(area1-b1-phone) 에 이미 있다',
    'E-ONB-24': '04-3 "다음" 이 아바타 작업까지 등록한다(운영 Cloud Tasks · OpenAI 비용) — 묶음 4',
    'E-ONB-25': '순서를 확인하려면 04-3 "다음" 으로 올려야 하고, 그때 아바타 작업이 등록된다 — 묶음 4',
    'E-ONB-33': '묶음 2 에 이미 있다',
    'E-ONB-55': '묶음 2 에 이미 있다(사진 세트가 있으면 그대로 다시 돌린다)',
    'E-GATE-47': 'B에뮬(네트워크 끊김) — 묶음 밖',
    'E-GATE-48': '사람 필요(Vision 고장은 운영에서 못 낸다)',
}


def photo_dir(run):
    return run.out.parent / '사진'


def missing(folder):
    """사진 세트 중 [folder] 에 없는 파일 이름."""
    return [name for name in PHOTO_SET if not (folder / name).is_file()]


def _photos(run, *names):
    """[names] 가 사진 세트 폴더에 다 있어야 한다 — 빠진 게 있으면 계정을 만들기 전에 blocked."""
    folder = photo_dir(run)
    absent = [name for name in dict.fromkeys(names) if not (folder / name).is_file()]
    if absent:
        raise Blocked(f'사진 세트 없음({folder}): {", ".join(absent)}')
    return [folder / name for name in dict.fromkeys(names)]


def _push(phone, run, *names):
    """[names] 를 폰 앱 캐시로 옮긴다(같은 이름은 한 번)."""
    serial = getattr(phone, 'serial', None)
    paths = _photos(run, *names)
    tools.adb(serial, 'shell', 'mkdir', '-p', REMOTE)
    for path in paths:
        tools.adb(serial, 'push', str(path), f'{REMOTE}/{path.name}')
    tools.adb(serial, 'shell', 'chmod', '755', REMOTE)  # 앱 사용자(run-as)가 읽을 수 있게
    # adb shell 은 뒤 인자를 따옴표 없이 이어 붙여 기기 셸에 넘긴다 — 한 문자열로 줘야 sh -c 가 통째로 간다.
    copies = ' && '.join(f'cp {REMOTE}/{path.name} {APP_DIR}/' for path in paths)
    tools.adb(serial, 'shell', f"run-as {tools.PACKAGE} sh -c 'mkdir -p {APP_DIR} && {copies}'")


def _attempts(run, account_id):
    return _rows(run, f'student_verification_attempts?profile_id=eq.{account_id}&order=id&select=result,reject_reason,reviewed_at')


def _files(run, bucket, account_id):
    return list(tools.storage_paths(run.cfg, run.key, bucket, account_id))


def _profile_state(run, account_id):
    return _one(run, f'profiles?id=eq.{account_id}&select=student_verification').get('student_verification')


def _reject(run, account_id, check):
    """대기 중인 제출을 반려 처리한다(사람이 대시보드에서 하는 일) — 이 계정 것만. 반려할 행이 없었으면 [check] 에 적는다."""
    pending = _rows(run, f'student_verification_attempts?profile_id=eq.{account_id}&result=eq.pending&select=id')
    check.that(pending, '반려할 대기 제출 행이 없음(앱이 제출을 못 보냈거나 서버가 바로 판정함)')
    _patch(run, f'student_verification_attempts?profile_id=eq.{account_id}&result=eq.pending',
           {'result': 'rejected', 'reject_reason': REJECT_REASON, 'reviewed_at': datetime.now(timezone.utc).isoformat()})
    _patch(run, f'profiles?id=eq.{account_id}', {'student_verification': 'rejected'})


# ── 학생증 제출 ──────────────────────────────────────────────────────────────────────────────────


def _submit(run, phone, photo, check, tab=None, on_step=None):
    """동의까지 끝낸 새 계정에서 앱이 [photo] 로 학생증을 낸다 → 계정."""
    _photos(run, photo)  # 계정을 만들기 전에 파일부터
    account = run.account('consented')
    _push(phone, run, photo)
    job = {'token_hash': run.link(account['email']), 'photo': photo, 'real_name': REAL_NAME}
    if tab:
        job['tab'] = tab
    midway = (lambda step: on_step(account)) if on_step else None
    _app(check, phone(midway=midway, **job))
    return account


def p_gate_34(run, phone):
    check = Check()
    account = _submit(run, phone, 'scenery.jpg', check)
    rows = _attempts(run, account['id'])
    check.that(not rows, f'얼굴 없는 사진인데 attempts {len(rows)}행(서버가 불렸다)')
    files = _files(run, 'student-id-temp', account['id'])
    check.that(not files, f'student-id-temp 파일 {len(files)}개')
    return check.result()


def p_gate_35(run, phone):
    check = Check()
    account = _submit(run, phone, 'cert_noface.jpg', check, tab='졸업증명서')
    rows = _attempts(run, account['id'])
    check.that(len(rows) == 1, f'졸업증명서 제출 뒤 attempts {len(rows)}행(서버 요청 1번이어야 함)')
    check.that(all(r['result'] in ('verified', 'pending') for r in rows), f'result {[r["result"] for r in rows]}')
    return check.result()


def p_gate_36(run, phone):
    check = Check()
    account = _submit(run, phone, 'id_ok.jpg', check)
    rows = _attempts(run, account['id'])
    check.that(len(rows) == 1 and rows[0]['result'] == 'verified' and rows[0]['reviewed_at'],
               f'attempts {rows} — verified 1행 · reviewed_at 이어야 함')
    state = _profile_state(run, account['id'])
    check.that(state == 'verified', f'profiles.student_verification {state}')
    files = _files(run, 'student-id-temp', account['id'])
    check.that(not files, f'student-id-temp 파일 {len(files)}개(즉시 지워져야 함)')
    return check.result()


def _held(run, phone, photo, label):
    """사람 검토로 넘어가야 하는 학생증 한 장. 디스코드 사유는 채널을 읽거나 사람이 본다(여기선 DB 만)."""
    check = Check()
    account = _submit(run, phone, photo, check)
    rows = _attempts(run, account['id'])
    check.that(len(rows) == 1 and rows[0]['result'] == 'pending', f'{label}: attempts {rows} — pending 1행이어야 함')
    state = _profile_state(run, account['id'])
    check.that(state == 'pending', f'{label}: profiles.student_verification {state}')
    files = _files(run, 'student-id-temp', account['id'])
    check.that(len(files) == 1, f'{label}: student-id-temp 파일 {len(files)}개(사람이 볼 1개가 남아야 함)')
    return check


def p_gate_37(run, phone):
    return _held(run, phone, 'id_name.jpg', '이름 다른 학생증').result()


def p_gate_38(run, phone):
    school = _held(run, phone, 'id_school.jpg', '학교 다른 학생증')
    blank = _held(run, phone, 'id_blank.jpg', '글자 없는 사진')
    school.problems += blank.problems
    return school.result('디스코드 사유(학교 이름 불일치 · 글자 못 찾음)는 채널을 보아야 한다')


def p_gate_44(run, phone):
    check = Check()
    account = _submit(run, phone, 'id_name.jpg', check, on_step=lambda acc: _reject(run, acc['id'], check))
    rows = _attempts(run, account['id'])
    check.that(rows and rows[-1]['result'] == 'rejected' and rows[-1]['reject_reason'] == REJECT_REASON, f'attempts {rows}')
    return check.result()


def p_gate_45(run, phone):
    check = Check()
    _photos(run, 'id_name.jpg')
    account = run.account('consented')
    _push(phone, run, 'id_name.jpg')
    for turn in range(3):
        job = {'token_hash': run.link(account['email']), 'photo': 'id_name.jpg', 'real_name': REAL_NAME, 'turn': turn}
        _app(check, phone(midway=lambda step: _reject(run, account['id'], check), **job), f'{turn + 1}번째')
    rows = _attempts(run, account['id'])
    check.that(len(rows) == 3 and all(r['result'] == 'rejected' for r in rows), f'attempts {[r["result"] for r in rows]} — 반려 3행이어야 함')
    return check.result()


# ── 04-2 프로필 사진 ─────────────────────────────────────────────────────────────────────────────


def _picker(*names, judge=None):
    """04-2 계정에서 앱이 [names] 를 갤러리에서 고른 것처럼 넣는다. 화면 판정은 앱이 한다."""
    def case(run, phone):
        check = Check()
        _photos(run, *names)
        account = run.account('kakao')
        _push(phone, run, *names)
        _app(check, phone(token_hash=run.link(account['email']), photos=list(names)))
        if judge:
            judge(run, account, check)
        return check.result()
    return case


def _nothing_bad_saved(run, account, check):
    """E-ONB-23 — 거절된 사진은 행도 파일도 남지 않는다(올라간 사진 수와 행 수가 같고 거절용은 못 들어간다)."""
    rows = _rows(run, f"profile_photos?profile_id=eq.{account['id']}&select=position")
    files = _files(run, 'profile-photos', account['id'])
    check.that(len(rows) == len(files), f'profile_photos {len(rows)}행 · profile-photos 파일 {len(files)}개')
    check.that(len(rows) <= 1 and 1 not in {r['position'] for r in rows},
               f'거절용 사진 자리(1번)까지 저장됨: profile_photos {sorted(r["position"] for r in rows)}')


# ── 사진 API ─────────────────────────────────────────────────────────────────────────────────────


def onb_26(run):
    check = Check()
    account = run.account('kakao')
    fields = {'position': 4, 'is_avatar_source': 'false'}
    jpeg = b'\xff\xd8\xff\xe0' + bytes(16) + b'\xff\xd9'
    big = b'\xff\xd8\xff' + bytes(10 * 1024 * 1024 + 1 - 3)  # 딱 10MB + 1바이트
    for label, fields_, name, data, status, detail in (
            ('자리 4', fields, 'p.jpg', jpeg, 422, None),
            ('GIF', {**fields, 'position': 0}, 'p.gif', b'GIF89a' + bytes(32), 400, PHOTO_UNREADABLE),
            ('10MB+1', {**fields, 'position': 0}, 'p.jpg', big, 400, PHOTO_UNREADABLE)):
        check.reply(label, _form(run, '/profile-onboarding/photos', account['token'], fields_, ('photo', name, data)), status, detail)
    rows = _rows(run, f"profile_photos?profile_id=eq.{account['id']}&select=position")
    files = _files(run, 'profile-photos', account['id'])
    check.that(not rows, f'profile_photos {len(rows)}행')
    check.that(not files, f'profile-photos 파일 {len(files)}개')
    return check.result()


PHONE = {
    'E-GATE-34': p_gate_34, 'E-GATE-35': p_gate_35, 'E-GATE-36': p_gate_36, 'E-GATE-37': p_gate_37, 'E-GATE-38': p_gate_38,
    'E-GATE-44': p_gate_44, 'E-GATE-45': p_gate_45,
    'E-ONB-20': _picker('face1.jpg', 'face2.jpg'),
    'E-ONB-21': _picker('face1.jpg', 'face2.jpg', 'face3.jpg', 'face4.jpg', 'face1.jpg'),  # 5장을 한 번에
    'E-ONB-22': _picker('face1.jpg', 'face2.jpg', 'scenery.jpg'),
    'E-ONB-23': _picker('face1.jpg', 'unsafe.jpg', judge=_nothing_bad_saved),
}
CASES = {'E-ONB-26': onb_26}

area1.PHONE.update(PHONE)
area1.CASES.update(CASES)
area1.BUNDLES['area1-b3'] = list(CASES) + list(PHONE)
