"""영역 1 묶음 3 — 사진 세트(04-2 사진 고르기 · 사진 API 경계).
기대값은 바탕화면 E2E_최종테스트_시나리오.md 영역 1 의 그 줄이다. 앱 쪽은 frontend/integration_test/area1_b3.dart 의 같은 번호.
3b 학생증 제출 가설(E-GATE-34~38 · 44 · 45)은 학생증 제거(10-17)로 앱 화면 · 서버 경로와 함께 뺐다.

사진 파일은 저장소에 없다 — 바탕화면 E2E_결과/사진/ 에 대장이 둔다(`python -m e2e photos` 가 빠진 이름을 알려 준다).
가설을 돌릴 때 필요한 파일만 폰 앱 캐시(`cache/e2e-photos/`)로 옮기고, 앱이 그 파일로 갤러리 훅을 갈아끼운다.
폰 가설은 area1.PHONE, API 가설은 area1.CASES 에 더해 `python -m e2e run area1-b3` 한 번으로 돈다.
"""

import contextlib

from e2e import area1, notify, tools
from e2e.area1 import Check, _app, _form, _rows
from e2e.tools import Blocked

PHOTO_SET = ('face1.jpg', 'face2.jpg', 'face3.jpg', 'face4.jpg', 'scenery.jpg', 'unsafe.jpg')
PHOTO_UNREADABLE = '사진을 다시 확인해 주세요'
REMOTE = '/data/local/tmp/e2e-photos'  # adb push 는 앱 폴더에 못 쓴다 — 여기 두었다가 run-as 로 앱 캐시에 옮긴다
APP_DIR = 'cache/e2e-photos'  # 앱의 getTemporaryDirectory()/e2e-photos

# 시나리오에 있지만 이 묶음에 안 넣은 것.
LEFT_OUT = {
    'E-ONB-24': '04-3 "다음" 이 아바타 작업까지 등록한다(운영 Cloud Tasks · OpenAI 비용) — 묶음 4',
    'E-ONB-25': '순서를 확인하려면 04-3 "다음" 으로 올려야 하고, 그때 아바타 작업이 등록된다 — 묶음 4',
    'E-ONB-33': '묶음 2 에 이미 있다',
    'E-ONB-55': '묶음 2 에 이미 있다(사진 세트가 있으면 그대로 다시 돌린다)',
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


def _allow_notifications(phone):
    """앞 묶음(영역 3)이 끝에서 알림 권한을 revoke 하면 권한 창이 앱을 가린다 — 폰 가설은 앱을 켜기 전에 이걸 부른다.
    안드로이드 12 이하는 권한이 없어 Blocked 가 나지만 권한 창도 없다 — 그대로 간다(area1_emu 와 같은 규칙)."""
    with contextlib.suppress(Blocked):
        notify.grant_notifications(getattr(phone, 'serial', None))


def _push(phone, run, *names):
    """[names] 를 폰 앱 캐시로 옮긴다(같은 이름은 한 번)."""
    _allow_notifications(phone)
    serial = getattr(phone, 'serial', None)
    paths = _photos(run, *names)
    tools.adb(serial, 'shell', 'mkdir', '-p', REMOTE)
    for path in paths:
        tools.adb(serial, 'push', str(path), f'{REMOTE}/{path.name}')
    tools.adb(serial, 'shell', 'chmod', '755', REMOTE)  # 앱 사용자(run-as)가 읽을 수 있게
    # adb shell 은 뒤 인자를 따옴표 없이 이어 붙여 기기 셸에 넘긴다 — 한 문자열로 줘야 sh -c 가 통째로 간다.
    copies = ' && '.join(f'cp {REMOTE}/{path.name} {APP_DIR}/' for path in paths)
    tools.adb(serial, 'shell', f"run-as {tools.PACKAGE} sh -c 'mkdir -p {APP_DIR} && {copies}'")


REGEN_PHOTO = 'face1.jpg'  # frontend/integration_test/regen_pick.dart 의 regenPhotoName 과 같은 파일 — 얼굴이 보여야 기기 안 얼굴 검사를 지난다


def regen_photo(run, phone):
    """아바타 다시 만들기가 사진부터 고르게 되어(15b-4 → 15b-5) 앱이 갤러리에서 고를 사진 한 장을 폰 앱 캐시로 옮긴다. 가설의 맨 앞(계정을 만들기
    전)에서 부른다 — 사진 세트가 없으면 계정을 만들기 전에 blocked. 만들기를 누르면 이 사진이 지금 아바타 원본 칸을 대신한다(서버 사진 목록이 바뀐다)."""
    _push(phone, run, REGEN_PHOTO)


def _files(run, bucket, account_id):
    return list(tools.storage_paths(run.cfg, run.key, bucket, account_id))


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
    'E-ONB-20': _picker('face1.jpg', 'face2.jpg'),
    'E-ONB-21': _picker('face1.jpg', 'face2.jpg', 'face3.jpg', 'face4.jpg', 'face1.jpg'),  # 5장을 한 번에
    'E-ONB-22': _picker('face1.jpg', 'face2.jpg', 'scenery.jpg'),
    'E-ONB-23': _picker('face1.jpg', 'unsafe.jpg', judge=_nothing_bad_saved),
}
CASES = {'E-ONB-26': onb_26}

area1.PHONE.update(PHONE)
area1.CASES.update(CASES)
area1.BUNDLES['area1-b3'] = list(CASES) + list(PHONE)
