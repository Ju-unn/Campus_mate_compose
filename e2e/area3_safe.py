"""영역 3 안전 API 가설 — E-SAFE 중 기기 없이 토큰 · 서비스 키로만 도는 18개(묶음 area3-safe-api).
기대값은 바탕화면 E2E_최종테스트_시나리오.md 영역 3 의 그 줄이다(10-04 갱신본).

가설 하나 = 함수 하나 `(run) -> (결과, 메모)`. 준비 도구는 영역 2(후보 · 카드 · 홈 계정)와 영역 3(매칭 · 메시지 · 리뷰)의 것을 쓴다.
신고 · 차단 · 후보의 **대상은 active 계정**이다 — basic 단계는 status 가 pending 이라 후보에도 카드에도 안 나와,
"빠졌다" 가 아무것도 증명하지 못한다(영역 3 검토 10-04). 그래서 대상은 홈 계정(`area2._person`)이고, "빠졌다" 앞에는
늘 "그 전에는 있었다" 를 본다 — 그 전부터 없으면 blocked.

디스코드 신고 줄의 "누적 신고자 수" 는 읽을 길이 없어(채널은 쓰기만) 서버와 같은 셈(열린 신고의 서로 다른 신고자)을
서비스 키로 DB 에서 센다. 투표 글 신고(E-SAFE-21 끝 문장)는 시험 글이 실사용자 피드에 보여 이번에 안 한다.
"""

import re
import uuid

from e2e import tools
from e2e.area1 import TINY_JPEG, Check, _api, _form, _patch, _rows
from e2e.area2 import _candidates, _card, _contact_block, _now, _person, _phone
from e2e.area3 import PROFILE_GONE, _as_user, _count, _link, _match, _messages, _pair, _review
from e2e.tools import Blocked

SUSPENDED = '이용이 제한된 계정이에요'
COUNT_NOTE = '신고자 수는 디스코드 대신 DB 로 셈(열린 신고의 서로 다른 신고자)'
# get_verified_caller(학생증 · 학과 · 정지 관문)를 거치는 경로 전부 — test_area3_safe 가 서버 코드와 대조한다.
VERIFIED_ROUTES = [
    'GET /profile-onboarding/nickname-availability', 'POST /profile-onboarding/basic-info',
    'POST /profile-onboarding/kakao-id', 'POST /profile-onboarding/photos', 'DELETE /profile-onboarding/photos/{position}',
    'POST /profile-onboarding/avatar/generate', 'GET /profile-onboarding/avatar/status',
    'POST /profile-onboarding/appearance-type', 'POST /profile-onboarding/interests', 'POST /profile-onboarding/my-traits',
    'POST /profile-onboarding/ideal-traits', 'POST /profile-onboarding/survey', 'POST /profile-onboarding/ideal-conditions',
    'POST /profile-onboarding/ideal-note', 'POST /profile-onboarding/bio-draft', 'POST /profile-onboarding/bio',
    'POST /profile-onboarding/acquisition', 'GET /profile-onboarding/next-step',
    'GET /matching/candidates',
    'GET /cards/today', 'POST /cards/{card_id}/decision', 'GET /cards/acceptances', 'POST /cards/acceptances/{card_id}',
    'GET /cards/notification-settings', 'PATCH /cards/notification-settings', 'GET /cards/matching-paused',
    'PATCH /cards/matching-paused', 'GET /cards/{card_id}',
    'GET /chat/conversations', 'GET /chat/matches/{match_id}', 'GET /chat/matches/{match_id}/messages',
    'POST /chat/matches/{match_id}/messages', 'PATCH /chat/matches/{match_id}/read', 'POST /chat/matches/{match_id}/leave',
    'POST /chat/matches/{match_id}/trust',
    'GET /home/summary',
    'GET /me/profile', 'GET /me/card-preview', 'POST /me/avatar/regenerate', 'PUT /me/photos', 'PATCH /me/profile',
    'POST /reports', 'POST /blocks/{profile_id}', 'GET /blocks', 'DELETE /blocks/{profile_id}', 'GET /profiles/{profile_id}',
    'POST /contact-blocks', 'GET /contact-blocks', 'DELETE /contact-blocks/{block_id}',
    'GET /community/polls', 'GET /community/polls/{poll_id}', 'POST /community/polls', 'POST /community/polls/{poll_id}/votes',
    'DELETE /community/polls/{poll_id}',
    'GET /account', 'GET /account/kakao-id',
    'GET /referral/my-code', 'POST /referral/redeem',
    'GET /friend-reviews/received', 'GET /friend-reviews/about/{profile_id}', 'GET /friend-reviews/targets/{profile_id}',
    'POST /friend-reviews', 'GET /friend-reviews/writable', 'GET /friend-reviews/written', 'DELETE /friend-reviews/{review_id}',
    'GET /heart-tasks', 'POST /heart-tasks/{task}/submissions',
]
# 정지 계정의 "DB 변화 0" 을 보는 표 — 계정 칸 이름.
OWNED = {'messages': 'sender_id', 'reports': 'reporter_id', 'blocks': 'blocker_id', 'contact_blocks': 'owner_id',
         'friend_reviews': 'reviewer_id', 'polls': 'author_id', 'poll_votes': 'voter_id', 'referrals': 'referee_id',
         'heart_task_submissions': 'profile_id', 'profile_photos': 'profile_id', 'profile_avatars': 'profile_id',
         'push_tokens': 'profile_id', 'notification_settings': 'profile_id', 'student_verification_attempts': 'profile_id'}


# ── 준비 · 읽기 ──────────────────────────────────────────────────────────────────────────────────────

def _report(run, who, kind, target_id, reason='spam', note=None):
    body = {'target_type': kind, 'target_id': target_id, 'reason': reason}
    if note is not None:
        body['reason_note'] = note
    return _api(run, 'POST', '/reports', who['token'], body)


def _hidden_at(run, account):
    return _rows(run, f"profiles?id=eq.{account['id']}&select=auto_hidden_at")[0]['auto_hidden_at']


def _open_reporters(run, account):
    """서버 count_open_reporters 와 같은 셈 — 디스코드 숫자 대신."""
    rows = _rows(run, f"reports?target_profile_id=eq.{account['id']}&status=eq.open&select=reporter_id")
    return len({r['reporter_id'] for r in rows if r['reporter_id']})


def _message_ids(run, match_id, sender):
    return [r['id'] for r in _rows(run, f"messages?match_id=eq.{match_id}&sender_id=eq.{sender['id']}&select=id&order=created_at")]


def _target(run, viewer=False):
    """신고 대상 T(활성 홈 계정)와, [viewer] 면 T 를 후보로 보는 F. 그 전부터 F 의 후보에 T 가 없으면 blocked."""
    t = _person(run, 'female')
    f = _person(run, 'male') if viewer else None
    if f and t['id'] not in _candidates(run, f):
        raise Blocked('준비: T 가 처음부터 F 의 후보가 아님')
    return t, f


def _reporters(run, t, n):
    """T 와 매칭된 신고자 n 명 — [(계정, 매칭 id)]. 신고는 매칭 이력이 있어야 된다."""
    out = []
    for _ in range(n):
        r = run.account('basic')
        out.append((r, _match(run, r, t)))
    return out


def _issue_owner(run, account):
    """오늘 카드를 받을 대상인가(card_issue_owners — 서비스 키 전용 읽기 함수)."""
    status, rows = tools.rest(run.cfg, run.key, 'GET', f"rpc/card_issue_owners?profile_id=eq.{account['id']}")
    if status != 200:
        raise Blocked(f'card_issue_owners 읽기 {status}')
    return bool(rows)


def _ids(reply, key):
    """GET /cards/today(`cards`) · /cards/acceptances(`acceptances`) 의 상대 id. 못 읽으면 blocked."""
    status, body = reply
    if status != 200:
        raise Blocked(f'{key} 읽기 {status}')
    return {row['profile']['profile_id'] for row in body.get(key, [])}


def _today(run, account):
    return _ids(_api(run, 'GET', '/cards/today', account['token']), 'cards')


def _inbox(run, account):
    return _ids(_api(run, 'GET', '/cards/acceptances', account['token']), 'acceptances')


def _accept(run, account, card_id):
    reply = _api(run, 'POST', f'/cards/{card_id}/decision', account['token'], {'decision': 'accept'})
    if reply[0] != 200:
        raise Blocked(f'카드 수락 {reply[0]}')


def _suspend(run, account):
    _patch(run, f"profiles?id=eq.{account['id']}", {'status': 'suspended'})


def _snapshot(run, account):
    """정지 계정의 프로필 두 행과 계정이 주인인 표의 행 수 — 앞뒤로 비교한다(내용은 메모에 안 적는다)."""
    me = account['id']
    shot = {'profiles': _rows(run, f'profiles?id=eq.{me}&select=*'),
            'profile_private': _rows(run, f'profile_private?profile_id=eq.{me}&select=*')}
    shot.update({table: _count(run, f'{table}?{column}=eq.{me}') for table, column in OWNED.items()})
    return shot


def _changed(before, after):
    return [k for k in before if before[k] != after[k]]


def _suspended_reply(check, label, reply):
    check.reply(label, reply, 403, SUSPENDED)
    if reply[0] == 403:
        check.that(reply.headers.get('x-account-status') == 'suspended',
                   f"{label}: X-Account-Status {reply.headers.get('x-account-status')}")


# ── 신고 ─────────────────────────────────────────────────────────────────────────────────────────────

def safe_10(run):
    check = Check()
    a, b, _ = _pair(run)
    for label, reason, note in (('기타 · 메모 없음', 'other', None), ('기타 · 201자', 'other', '가' * 201), ('없는 사유', 'hate', None)):
        check.reply(label, _report(run, a, 'profile', b['id'], reason, note), 422)
    check.that(_count(run, f"reports?reporter_id=eq.{a['id']}") == 0, '422 뒤 reports 새 행이 생김')
    check.that(_count(run, f"blocks?blocker_id=eq.{a['id']}") == 0, '422 뒤 blocks 새 행이 생김')
    check.reply('광고 · 메모 x', _report(run, a, 'profile', b['id'], 'spam', 'x'), 201)
    rows = _rows(run, f"reports?reporter_id=eq.{a['id']}&select=reason,reason_note")
    got = [(r['reason'], r['reason_note']) for r in rows]
    check.that(got == [('spam', None)], f'reports {got}(기대 spam · reason_note null)')
    return check.result()


def safe_12(run):
    check = Check()
    a, c = run.account('basic'), run.account('basic')
    check.reply('매칭 없는 C', _report(run, a, 'profile', c['id']), 404, PROFILE_GONE)
    check.reply('나 자신', _report(run, a, 'profile', a['id']), 404, PROFILE_GONE)
    check.that(_count(run, f"reports?reporter_id=eq.{a['id']}") == 0, 'reports 새 행이 생김')
    check.that(_count(run, f"blocks?blocker_id=eq.{a['id']}") == 0, 'blocks 새 행이 생김')
    d = run.account('basic')
    _match(run, a, d)
    check.reply('대조군(매칭된 D)', _report(run, a, 'profile', d['id']), 201)  # 이게 404 면 위의 404 는 규칙 때문이 아니다
    return check.result()


def safe_14(run):
    check = Check()
    a, b, match_id = _pair(run)
    _messages(run, match_id, b, 2)
    first, second = _message_ids(run, match_id, b)
    for label, kind, target in (('프로필', 'profile', b['id']), ('메시지 1', 'message', first), ('메시지 2', 'message', second)):
        check.reply(label, _report(run, a, kind, target), 201)
    check.that((n := _count(run, f"reports?reporter_id=eq.{a['id']}")) == 3, f'reports {n}행(기대 3)')
    check.that((n := _count(run, f"blocks?blocker_id=eq.{a['id']}")) == 1, f'blocks {n}행(기대 1)')
    check.that((n := _count(run, f'messages?match_id=eq.{match_id}&kind=eq.left')) == 1, f'나감 줄 {n}개(기대 1)')
    return check.result()


# ── 자동 가림 ────────────────────────────────────────────────────────────────────────────────────────

def safe_19(run):
    check = Check()
    t, f = _target(run, viewer=True)
    for i, (r, _) in enumerate(_reporters(run, t, 2), 1):
        check.reply(f'신고 {i}', _report(run, r, 'profile', t['id']), 201)
    check.that(_hidden_at(run, t) is None, f'신고자 2명에 auto_hidden_at {_hidden_at(run, t)}')
    check.that((n := _open_reporters(run, t)) == 2, f'신고자 {n}명(기대 2)')
    check.that(t['id'] in _candidates(run, f), 'F 의 후보에서 T 가 빠짐')
    return check.result(COUNT_NOTE)


def safe_20(run):
    check = Check()
    t, _ = _target(run)
    (c, c_match), (d, _) = _reporters(run, t, 2)
    _messages(run, c_match, t, 2)
    targets = [('profile', t['id']), *(('message', m) for m in _message_ids(run, c_match, t))]
    for kind, target in targets:
        check.reply(f'C 의 {kind} 신고', _report(run, c, kind, target), 201)
    check.reply('D 의 프로필 신고', _report(run, d, 'profile', t['id']), 201)
    check.that((n := _open_reporters(run, t)) == 2, f'신고자 {n}명(기대 2 — C 3건은 1명)')
    check.that(_hidden_at(run, t) is None, f'auto_hidden_at {_hidden_at(run, t)}(신고 4건이지만 2명)')
    return check.result(COUNT_NOTE)


def safe_21(run):
    check = Check()
    t, _ = _target(run)
    e = run.account('basic')
    _link(run, t, e)  # T 가 E 를 추천 — 지인 리뷰를 쓸 수 있는 사이
    review = _review(run, t, e)
    (c, _), (d, _), (g, _) = _reporters(run, t, 3)
    check.reply('C 프로필 신고', _report(run, c, 'profile', t['id']), 201)
    check.reply('D 프로필 신고', _report(run, d, 'profile', t['id']), 201)
    check.reply('E 리뷰 신고(3번째)', _report(run, e, 'friend_review', review), 201)
    check.that((n := _open_reporters(run, t)) == 3, f'리뷰 신고 뒤 신고자 {n}명(기대 3)')
    check.that(_hidden_at(run, t) is None, f'리뷰 신고만으로 auto_hidden_at {_hidden_at(run, t)}')
    check.reply('G 프로필 신고', _report(run, g, 'profile', t['id']), 201)
    check.that(_hidden_at(run, t) is not None, 'G 의 프로필 신고 뒤에도 auto_hidden_at 이 비어 있음')
    return check.result(f'{COUNT_NOTE} · 투표 글 판은 안 봄')


def safe_23(run):
    check = Check()
    t, f = _person(run, 'female'), _person(run, 'male')
    _card(run, f, t)  # F 가 받은 T 카드
    _accept(run, t, _card(run, t, f))  # T 가 자기 카드의 F 를 수락 → F 수락함에 T
    if t['id'] not in _today(run, f) or t['id'] not in _inbox(run, f) or not _issue_owner(run, t):
        raise Blocked('준비: 가리기 전에 F 의 오늘 카드 · 수락함 · 카드 지급 대상 중 T 가 없는 곳이 있음')
    _patch(run, f"profiles?id=eq.{t['id']}", {'auto_hidden_at': _now().isoformat()})
    check.that(t['id'] not in _today(run, f), 'F 의 오늘 카드에 가려진 T 가 남음')
    check.that(t['id'] not in _inbox(run, f), 'F 의 수락함에 가려진 T 가 남음')
    check.that(not _issue_owner(run, t), '가려진 T 가 카드 지급 대상(card_issue_owners)에 있음')
    return check.result()


def safe_24(run):
    check = Check()
    t, f = _target(run, viewer=True)
    for i, (r, _) in enumerate(_reporters(run, t, 3), 1):
        check.reply(f'신고 {i}', _report(run, r, 'profile', t['id']), 201)
    check.that(_hidden_at(run, t) is not None, '준비: 3명 신고 뒤 가려지지 않음(E-SAFE-18)')
    _patch(run, f"reports?target_profile_id=eq.{t['id']}", {'status': 'dismissed', 'resolved_at': _now().isoformat()})
    _patch(run, f"profiles?id=eq.{t['id']}", {'auto_hidden_at': None})
    check.that(t['id'] in _candidates(run, f), '기각 · 해제 뒤 F 의 후보에 T 가 없음')
    (h, _), = _reporters(run, t, 1)
    check.reply('H 신고', _report(run, h, 'profile', t['id']), 201)
    check.that((n := _open_reporters(run, t)) == 1, f'기각 뒤 신고자 {n}명(기대 1)')
    check.that(_hidden_at(run, t) is None, f'기각 뒤 새 신고 1건에 auto_hidden_at {_hidden_at(run, t)}')
    return check.result(COUNT_NOTE)


# ── 차단 ─────────────────────────────────────────────────────────────────────────────────────────────

def safe_29(run):
    check = Check()
    a, b, _ = _pair(run)
    c = run.account('basic')
    check.reply('매칭 없는 C', _api(run, 'POST', f"/blocks/{c['id']}", a['token']), 404, PROFILE_GONE)
    check.reply('나 자신', _api(run, 'POST', f"/blocks/{a['id']}", a['token']), 404, PROFILE_GONE)
    check.reply('B 첫 차단', _api(run, 'POST', f"/blocks/{b['id']}", a['token']), 200)
    check.reply('B 두 번째', _api(run, 'POST', f"/blocks/{b['id']}", a['token']), 200)
    rows = _rows(run, f"blocks?blocker_id=eq.{a['id']}&select=blocked_id")
    check.that([r['blocked_id'] for r in rows] == [b['id']], f'blocks {len(rows)}행(기대 B 1행)')
    return check.result()


def safe_33(run):
    check = Check()
    a, b = _person(run, 'male'), _person(run, 'female')
    if b['id'] not in _candidates(run, a):
        raise Blocked('준비: 매칭 전부터 서로 후보가 아님')
    _match(run, a, b)
    check.reply('차단', _api(run, 'POST', f"/blocks/{b['id']}", a['token']), 200)
    check.reply('해제', _api(run, 'DELETE', f"/blocks/{b['id']}", a['token']), 200)
    check.that(_count(run, f"blocks?blocker_id=eq.{a['id']}") == 0, '해제 뒤 blocks 가 남음')
    check.that(b['id'] not in _candidates(run, a), '해제 뒤 A 의 후보에 B 가 다시 나옴')
    check.that(a['id'] not in _candidates(run, b), '해제 뒤 B 의 후보에 A 가 다시 나옴')
    return check.result('코드대로 서로 후보에 없음 — 해제 확인 문구 "이 상대가 다시 카드에 나타날 수 있어요"(block_list_screen.dart:95)와 '
                        '다르다(⚠ 4, 문구 결정 필요)')


def safe_34(run):
    check = Check()
    a, b, _ = _pair(run)
    trials = {'blocks': {'blocker_id': a['id'], 'blocked_id': b['id']},
              'reports': {'reporter_id': a['id'], 'target_type': 'profile', 'target_id': b['id'],
                          'target_profile_id': b['id'], 'target_snapshot': {}, 'reason': 'spam'},
              'contact_blocks': {'owner_id': a['id'], 'contact_hmac': '\\x00', 'key_version': 1}}
    for table, row in trials.items():
        path = f"{table}?{OWNED[table]}=eq.{a['id']}"
        before = _count(run, path)
        status, body = _as_user(run, a, 'GET', f'{table}?select=*')
        # 0행(200)은 거부가 아니다 — 앱에는 권한이 아예 없어야 한다(create_*.sql 의 revoke).
        check.that(status in (401, 403), f'{table} select: {status}(기대 거부 401/403)')
        status, body = _as_user(run, a, 'POST', table, row)
        check.that(status in (401, 403), f'{table} insert: {status}(기대 거부 401/403)')
        check.that(_count(run, path) == before, f'{table} 새 행이 생김')
    return check.result()


# ── 지인 차단 ────────────────────────────────────────────────────────────────────────────────────────

def safe_44(run):
    check = Check()
    a = run.account('basic')
    check.reply('201개', _api(run, 'POST', '/contact-blocks', a['token'], {'numbers': [_phone() for _ in range(201)]}), 422)
    check.reply('빈 목록', _api(run, 'POST', '/contact-blocks', a['token'], {'numbers': []}), 422)
    check.that(_count(run, f"contact_blocks?owner_id=eq.{a['id']}") == 0, 'contact_blocks 새 행이 생김')
    # 대조군: 크기만 맞으면 받는다. 휴대전화가 아닌 번호라 아무 행도 안 생긴다(safety/router.py — null 자리).
    check.reply('대조군(1개)', _api(run, 'POST', '/contact-blocks', a['token'], {'numbers': ['02-123-4567']}), 200)
    return check.result()


def safe_47(run):
    check = Check()
    b, c = run.account('basic'), run.account('basic')
    status, body = _api(run, 'POST', '/contact-blocks', b['token'], {'numbers': [_phone()]})
    row = ((body or {}).get('blocks') or [None])[0]
    if status != 200 or not row:
        raise Blocked(f'B 의 지인 차단 {status}')
    path = f"contact_blocks?id=eq.{row['id']}"
    check.reply('C 가 B 의 줄 해제', _api(run, 'DELETE', f"/contact-blocks/{row['id']}", c['token']), 200)
    check.that(_count(run, path) == 1, 'C 의 해제로 B 의 줄이 지워짐')
    check.reply('대조군: B 본인 해제', _api(run, 'DELETE', f"/contact-blocks/{row['id']}", b['token']), 200)
    check.that(_count(run, path) == 0, '대조군: B 본인 해제로도 안 지워짐 — 위의 "그대로" 는 증거가 못 된다')
    return check.result()


def safe_48(run):
    check = Check()
    b = _person(run, 'male')
    f, w = _person(run, 'female', phone=_phone()), _person(run, 'female', phone=_phone())  # W = 해시가 있는 대조군
    got = _candidates(run, b)
    if f['id'] not in got or w['id'] not in got:
        raise Blocked('준비: 지인 차단 전부터 B 의 후보에 F · W 가 없음')
    _patch(run, f"profile_private?profile_id=eq.{f['id']}", {'phone_hmac': None})
    _contact_block(run, b, f['phone'], w['phone'])
    got = _candidates(run, b)
    check.that(f['id'] in got, '번호 해시가 없는 F 가 B 의 후보에서 빠짐')
    check.that(w['id'] not in got, '대조군: 해시가 있는 W 도 그대로 — 지인 차단이 아무도 안 거른다')
    return check.result('알려진 성질(phone_hmac null 은 안 걸림)')


def safe_49(run):
    check = Check()
    b = _person(run, 'male')
    f = _person(run, 'female', phone=_phone())
    _card(run, b, f)               # B 의 오늘 카드에 F
    _accept(run, f, _card(run, f, b))  # F 가 B 를 수락 → B 수락함에 F
    _card(run, f, b)               # F 의 오늘 카드에 B
    _accept(run, b, _card(run, b, f))  # B 가 F 를 수락 → F 수락함에 B
    seen = {'B 의 오늘 카드': (b, _today, f), 'B 의 수락함': (b, _inbox, f),
            'F 의 오늘 카드': (f, _today, b), 'F 의 수락함': (f, _inbox, b)}
    missing = [label for label, (who, read, other) in seen.items() if other['id'] not in read(run, who)]
    if missing:
        raise Blocked(f"준비: 지인 차단 전부터 없음 — {', '.join(missing)}")
    _contact_block(run, b, f['phone'])
    for label, (who, read, other) in seen.items():
        check.that(other['id'] not in read(run, who), f'지인 차단 뒤 {label}에 상대가 남음')
    return check.result()


# ── 정지 ─────────────────────────────────────────────────────────────────────────────────────────────

def _concrete(route):
    """'GET /cards/{card_id}' → ('GET', '/cards/<새 uuid>'). 숫자 · 이름 자리는 그 꼴로."""
    fixed = {'position': '0', 'task': 'everytime_post', 'token': 'e2e'}
    method, path = route.split(' ', 1)
    return method, re.sub(r'\{(\w+)\}', lambda m: fixed.get(m.group(1), str(uuid.uuid4())), path)


def safe_51(run):
    """본문은 보내지 않는다 — 관문이 열려 있으면 본문 검사(422)에서 멈춰 아무것도 쓰지 않는다."""
    check = Check()
    a = run.account('basic')  # 학생증 · 학과까지 끝 — 정지 말고는 관문을 다 통과한다
    _suspend(run, a)
    before = _snapshot(run, a)
    for route in VERIFIED_ROUTES:
        _suspended_reply(check, route, _api(run, *_concrete(route), a['token']))
    check.that(not (changed := _changed(before, _snapshot(run, a))), f'DB 가 바뀜: {changed}')
    push = _api(run, 'POST', '/cards/push-tokens', a['token'], {'token': f"e2e-{a['n']}", 'platform': 'android'})
    return check.result(f'푸시 토큰 등록은 로그인만 보는 문이라 정지에도 {push[0]}(A7) — 시나리오 괄호의 "푸시 토큰" 은 옛 기대')


def safe_52(run):
    check = Check()
    a = run.account('basic')
    _suspend(run, a)
    before = _snapshot(run, a)
    _suspended_reply(check, '④ POST /student-verification',
                     _form(run, '/student-verification', a['token'], {'real_name': '홍길동'}, ('photo', 'id.jpg', TINY_JPEG)))
    _suspended_reply(check, '⑤ POST /school-info',
                     _api(run, 'POST', '/school-info', a['token'], {'department': '경영학과', 'student_number': f"e2e{a['n']}x"}))
    check.that(not (changed := _changed(before, _snapshot(run, a))), f'④⑤ 뒤 DB 가 바뀜: {changed}')
    for label, method, path, body in (('① GET /me/verification-status', 'GET', '/me/verification-status', None),
                                      ('② POST /me/consents', 'POST', '/me/consents', {'agreed': ['terms', 'privacy']}),
                                      ('③ POST /account/withdraw', 'POST', '/account/withdraw', None)):  # 탈퇴는 마지막
        status, body = _api(run, method, path, a['token'], body)
        check.that(status != 403 and status < 500, f'{label}: {status}(기대 열림)')
    return check.result('①②③ 은 정지에도 열림 — 설계 확인용(⚠ 6). ③ 으로 A 는 탈퇴 · signup_blocks 무기한 1행(뒷정리가 지움)')


def safe_54(run):
    check = Check()
    a, f = _person(run, 'female'), _person(run, 'male')
    card = _card(run, f, a) if a['id'] in _candidates(run, f) and _issue_owner(run, a) else None
    if card is None or a['id'] not in _today(run, f):
        raise Blocked('준비: 정지 전부터 F 의 후보 · 오늘 카드 · 카드 지급 대상 중 A 가 없는 곳이 있음')
    _suspend(run, a)
    check.that(a['id'] not in _today(run, f), 'F 의 오늘 카드에 정지된 A 가 남음')
    check.that(not _issue_owner(run, a), '정지된 A 가 카드 지급 대상(card_issue_owners)에 있음')
    # 살아 있는 카드도 후보에서 빼는 규칙이라, 카드를 지운 뒤에 봐야 정지 때문에 빠졌는지 안다.
    status, _ = tools.rest(run.cfg, run.key, 'DELETE', f'daily_cards?id=eq.{card}')
    if status >= 300:
        raise Blocked(f'준비: 카드 지우기 {status}')
    check.that(a['id'] not in _candidates(run, f), 'F 의 후보에 정지된 A 가 있음')
    return check.result()


CASES = {
    'E-SAFE-10': safe_10, 'E-SAFE-12': safe_12, 'E-SAFE-14': safe_14, 'E-SAFE-19': safe_19, 'E-SAFE-20': safe_20,
    'E-SAFE-21': safe_21, 'E-SAFE-23': safe_23, 'E-SAFE-24': safe_24, 'E-SAFE-29': safe_29, 'E-SAFE-33': safe_33,
    'E-SAFE-34': safe_34, 'E-SAFE-44': safe_44, 'E-SAFE-47': safe_47, 'E-SAFE-48': safe_48, 'E-SAFE-49': safe_49,
    'E-SAFE-51': safe_51, 'E-SAFE-52': safe_52, 'E-SAFE-54': safe_54,
}
BUNDLES = {'area3-safe-api': list(CASES)}


def attempt(run, case):
    """가설 하나. 준비가 안 되면 blocked."""
    try:
        return CASES[case](run)
    except Blocked as e:
        return 'blocked', str(e)
