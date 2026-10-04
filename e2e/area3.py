"""영역 3(채팅 · 지인 리뷰 · 안전) API 가설 — 기기 없이 토큰 · 서비스 키로만 도는 것 중 채팅 · 리뷰 쪽 15개(묶음 area3-api).
기대값은 바탕화면 E2E_최종테스트_시나리오.md 영역 3 의 그 줄이다(10-04 갱신본).

가설 하나 = 함수 하나 `(run) -> (결과, 메모)`. 계정은 [Run.account] 로 그때그때 새로 만든다.
공장에 없는 준비(매칭 · 메시지 · 추천 연결 · 리뷰)는 서비스 키로 DB 에 직접 넣는다 — 시험 계정 행만 건드린다.

이번에 안 하는 것: E-CHAT-68(E-CHAT-55 의 배치가 먼저 돌아야 한다) · 배치 · 시간조작 가설 · E-SAFE(안전담당 몫).
E-CHAT-63 · 70 의 "Realtime 구독 후 한 건" 은 하지 않는다 — 표준 라이브러리에 웹소켓이 없다. 같은 messages 읽기 정책(RLS)이
구독에도 걸리므로(create_messages.sql 마지막 주석) 표를 읽어 0행인지만 보고, 메모에 그렇게 적는다.
"""

import uuid
from datetime import datetime, timedelta, timezone

from e2e import tools
from e2e.area1 import Check, _api, _rows
from e2e.tools import Blocked

NOT_FOUND = '대화를 찾을 수 없어요'
CHAT_LEFT = '이미 나간 대화예요'
PROFILE_GONE = '프로필을 찾을 수 없어요'
REVIEW_GONE = '리뷰를 찾을 수 없어요'
REALTIME_NOTE = 'Realtime 구독은 안 봄(웹소켓 없음) — 같은 읽기 정책이라 표 읽기만'


# ── 준비 ─────────────────────────────────────────────────────────────────────────────────────────────

def _insert(run, table, rows):
    status, got = tools.rest(run.cfg, run.key, 'POST', table, rows)
    if status >= 300:
        raise Blocked(f'{table} 넣기 {status} {got}')


def _patch(run, path, body):
    status, got = tools.rest(run.cfg, run.key, 'PATCH', path, body)
    if status >= 300:
        raise Blocked(f'{path} 바꾸기 {status} {got}')


def _match(run, x, y):
    """두 계정의 매칭. matches 는 profile_a < profile_b 로만 저장된다(matches_pair_order)."""
    a, b = sorted((x['id'], y['id']))
    match_id = str(uuid.uuid4())
    _insert(run, 'matches', {'id': match_id, 'profile_a': a, 'profile_b': b})
    _insert(run, 'match_participants', [{'match_id': match_id, 'profile_id': a}, {'match_id': match_id, 'profile_id': b}])
    return match_id


def _link(run, referrer, referee):
    """추천 연결 — 이 행이 있으면 지인 리뷰를 쓸 수 있는 사이다(방향 상관없음).
    상대(referee)는 active 로 올린다: basic 단계 계정은 status 가 pending 이라 서버(_writable_target → is_active)가
    누구에게나 404 를 내고, 그러면 차단 · 정지 가설의 404 가 아무것도 증명하지 못한다(검토 10-04)."""
    _insert(run, 'referrals', {'referee_id': referee['id'], 'referrer_id': referrer['id']})
    _patch(run, f"profiles?id=eq.{referee['id']}", {'status': 'active'})


def _messages(run, match_id, sender, count):
    """[sender] 가 보낸 글 [count] 건 — 시각이 1초씩 달라 순서가 정해진다."""
    now = datetime.now(timezone.utc)
    _insert(run, 'messages', [{'match_id': match_id, 'sender_id': sender['id'], 'body': f'E2E-{i}',
                               'created_at': (now - timedelta(seconds=count - i)).isoformat()} for i in range(count)])


def _review(run, reviewer, reviewee, **extra):
    """리뷰 한 줄을 DB 에 직접(연결 검사 없이). id 를 미리 정해 두고 돌려준다."""
    review_id = str(uuid.uuid4())
    _insert(run, 'friend_reviews', {'id': review_id, 'reviewer_id': reviewer['id'], 'reviewee_id': reviewee['id'],
                                    'tags': ['대화가 편해요'], **extra})
    return review_id


def _drop_reports(run, review, check):
    """서버가 어긋나 신고가 만들어졌으면 지운다 — reports 는 계정을 지워도 cascade 로 안 지워져(set null) 남는다."""
    made = _count(run, f'reports?target_id=eq.{review}')
    check.that(made == 0, f'reports {made}행이 생김 — 지움')
    if made:
        tools.rest(run.cfg, run.key, 'DELETE', f'reports?target_id=eq.{review}')


def _count(run, path):
    return len(_rows(run, f'{path}&select=id' if '?' in path else f'{path}?select=id'))


def _as_user(run, account, method, path, body=None):
    """앱과 같은 길 — 공개 키 + 사용자 토큰으로 Supabase 표를 직접 부른다(RLS · 권한을 거친다)."""
    return tools.rest(run.cfg, run.cfg['SUPABASE_ANON_KEY'], method, path, body, token=account['token'])


def _send(run, account, match_id, body):
    return _api(run, 'POST', f'/chat/matches/{match_id}/messages', account['token'], {'body': body})


def _control(run, a, check):
    """대조군 — 차단 · 정지가 없는 평범한 연결 상대에게는 쓰기가 201. 이게 404 면 아래 404 들은 규칙 때문이 아니다."""
    d = run.account('basic')
    _link(run, a, d)
    check.reply('대조군(평범한 상대)', _review_post(run, a, d), 201)


def _review_post(run, account, reviewee, tags=None, comment=None):
    body = {'reviewee_id': reviewee['id'], 'tags': tags if tags is not None else ['대화가 편해요']}
    if comment is not None:
        body['comment'] = comment
    return _api(run, 'POST', '/friend-reviews', account['token'], body)


def _pair(run):
    """(A, B, 매칭 id) — 둘 다 basic 단계."""
    a, b = run.account('basic'), run.account('basic')
    return a, b, _match(run, a, b)


# ── 채팅 ─────────────────────────────────────────────────────────────────────────────────────────────

def chat_14(run):
    check = Check()
    a, b, match_id = _pair(run)
    check.reply('1001자', _send(run, a, match_id, '가' * 1001), 422)
    check.that(_count(run, f'messages?match_id=eq.{match_id}') == 0, 'messages 새 행이 생김')
    return check.result()


def chat_21(run):
    check = Check()
    a, b, match_id = _pair(run)
    _messages(run, match_id, b, 51)  # 한 페이지(50)보다 하나 많이 — 500 을 요청해도 50 에서 잘리는지 보인다
    base = f'/chat/matches/{match_id}/messages'
    check.reply('limit=0', _api(run, 'GET', f'{base}?limit=0', a['token']), 422)
    status, body = _api(run, 'GET', f'{base}?limit=500', a['token'])
    check.that(status == 200, f'limit=500: {status}')
    got = len((body or {}).get('messages', [])) if status == 200 else None
    check.that(got is None or got == 50, f'limit=500: {got}건(기대 50)')
    return check.result()


def chat_63(run):
    check = Check()
    a, b, match_id = _pair(run)
    _messages(run, match_id, b, 1)
    check.reply('나가기', _api(run, 'POST', f'/chat/matches/{match_id}/leave', a['token']), 200)
    check.reply('방 읽기', _api(run, 'GET', f'/chat/matches/{match_id}', a['token']), 404, NOT_FOUND)
    check.reply('메시지 읽기', _api(run, 'GET', f'/chat/matches/{match_id}/messages', a['token']), 404, NOT_FOUND)
    status, rows = _as_user(run, a, 'GET', f'messages?match_id=eq.{match_id}&select=id')
    check.that(status == 200 and rows == [], f'messages 직접 읽기: {status} {rows}')
    return check.result(REALTIME_NOTE)


def chat_64(run):
    check = Check()
    a, b, match_id = _pair(run)
    check.reply('첫 나가기', _api(run, 'POST', f'/chat/matches/{match_id}/leave', a['token']), 200)
    check.reply('두 번째 나가기', _api(run, 'POST', f'/chat/matches/{match_id}/leave', a['token']), 409, CHAT_LEFT)
    left = _count(run, f'messages?match_id=eq.{match_id}&kind=eq.left')
    check.that(left == 1, f'나감 줄 {left}개(기대 1)')
    return check.result()


def chat_70(run):
    check = Check()
    a, b, match_id = _pair(run)
    c = run.account('basic')  # 매칭 밖 제3자
    _messages(run, match_id, a, 1)
    check.reply('방 읽기', _api(run, 'GET', f'/chat/matches/{match_id}', c['token']), 404, NOT_FOUND)
    check.reply('메시지 읽기', _api(run, 'GET', f'/chat/matches/{match_id}/messages', c['token']), 404, NOT_FOUND)
    status, rows = _as_user(run, c, 'GET', f'messages?match_id=eq.{match_id}&select=id')
    check.that(status == 200 and rows == [], f'messages 직접 읽기: {status} {rows}')
    return check.result(REALTIME_NOTE)


def chat_71(run):
    check = Check()
    a, b, match_id = _pair(run)
    status, body = _as_user(run, a, 'POST', 'messages', {'match_id': match_id, 'sender_id': a['id'], 'body': 'E2E-앱직접쓰기'})
    check.that(status in (401, 403), f'직접 쓰기: {status}(기대 거부 401/403) {body}')
    check.that(_count(run, f'messages?match_id=eq.{match_id}') == 0, 'messages 새 행이 생김')
    return check.result()


# ── 지인 리뷰 ────────────────────────────────────────────────────────────────────────────────────────

def rev_08(run):
    check = Check()
    a, b = run.account('basic'), run.account('basic')
    _link(run, a, b)
    check.reply('작성', _review_post(run, a, b, comment='가' * 100 + ' '), 201)
    rows = _rows(run, f"friend_reviews?reviewer_id=eq.{a['id']}&select=comment")
    check.that(len(rows) == 1, f'friend_reviews {len(rows)}행')
    comment = rows[0]['comment'] if rows else ''
    check.that(comment == '가' * 100, f'comment {len(comment or "")}자 · 끝 공백 {"있음" if comment != (comment or "").rstrip() else "없음"}')
    return check.result()


def rev_09(run):
    check = Check()
    a, b = run.account('basic'), run.account('basic')
    _link(run, a, b)
    trials = (('태그 0개', [], None), ('태그 4개', ['약속을 잘 지켜요', '대화가 편해요', '배려가 깊어요', '성실해요'], None),
              ('목록 밖 태그', ['잘생겼어요'], None), ('같은 태그 두 번', ['성실해요', '성실해요'], None),
              ('한마디 101자', ['성실해요'], '가' * 101))
    for label, tags, comment in trials:
        check.reply(label, _review_post(run, a, b, tags, comment), 422)
    check.that(_count(run, f"friend_reviews?reviewer_id=eq.{a['id']}") == 0, 'friend_reviews 새 행이 생김')
    return check.result()


def rev_13(run):
    check = Check()
    a = run.account('basic')
    check.reply('자기 자신', _review_post(run, a, a), 404, PROFILE_GONE)
    return check.result()


def rev_14(run):
    check = Check()
    a, b, c = run.account('basic'), run.account('basic'), run.account('basic')
    _link(run, a, b)
    _link(run, a, c)
    _match(run, a, b)  # 차단은 매칭 이력이 있어야만 된다
    _match(run, a, c)
    check.reply('B 가 A 차단', _api(run, 'POST', f"/blocks/{a['id']}", b['token']), 200)
    check.reply('A 가 C 차단', _api(run, 'POST', f"/blocks/{c['id']}", a['token']), 200)
    _control(run, a, check)
    check.reply('나를 차단한 B', _review_post(run, a, b), 404, PROFILE_GONE)
    check.reply('내가 차단한 C', _review_post(run, a, c), 404, PROFILE_GONE)
    return check.result()


def rev_15(run):
    check = Check()
    a, b, c = run.account('basic'), run.account('basic'), run.account('basic')
    _link(run, a, b)
    _link(run, a, c)
    _patch(run, f"profiles?id=eq.{b['id']}", {'status': 'suspended'})
    # profiles_withdrawn_at_check — 탈퇴 상태와 withdrawn_at 은 함께 채운다
    _patch(run, f"profiles?id=eq.{c['id']}", {'status': 'withdrawn', 'withdrawn_at': datetime.now(timezone.utc).isoformat()})
    _control(run, a, check)
    check.reply('정지한 상대', _review_post(run, a, b), 404, PROFILE_GONE)
    check.reply('탈퇴한 상대', _review_post(run, a, c), 404, PROFILE_GONE)
    return check.result()


def rev_28(run):
    check = Check()
    a, b, c = run.account('basic'), run.account('basic'), run.account('basic')
    _link(run, a, b)
    status, body = _review_post(run, a, b)
    check.that(status == 201 and bool((body or {}).get('id')), f'첫 작성: {status} {body}')
    first = (body or {}).get('id')
    if first:
        check.reply('내 리뷰 지우기', _api(run, 'DELETE', f'/friend-reviews/{first}', a['token']), 204)
        check.reply('이미 지운 리뷰', _api(run, 'DELETE', f'/friend-reviews/{first}', a['token']), 404, REVIEW_GONE)
    status, body = _review_post(run, a, b)  # 지웠으니 다시 쓸 수 있다
    second = (body or {}).get('id')
    check.that(status == 201 and bool(second), f'다시 작성: {status} {body}')
    others = _review(run, c, b)  # C 가 B 에게 쓴 리뷰
    if second:
        check.reply('받은 사람이 지우기', _api(run, 'DELETE', f'/friend-reviews/{second}', b['token']), 404, REVIEW_GONE)
    check.reply('남의 리뷰 지우기', _api(run, 'DELETE', f'/friend-reviews/{others}', a['token']), 404, REVIEW_GONE)
    left = {r['id'] for r in _rows(run, f"friend_reviews?reviewee_id=eq.{b['id']}&select=id")}
    check.that(left == {x for x in (second, others) if x}, f'남은 리뷰 {sorted(left)}(기대: 다시 쓴 것 · C 의 것)')
    return check.result()


def rev_38(run):
    check = Check()
    a, b, c = run.account('basic'), run.account('basic'), run.account('basic')
    review = _review(run, a, b)  # A 가 B 에게 쓴 리뷰
    _match(run, b, c)
    body = {'target_type': 'friend_review', 'target_id': review, 'reason': 'spam'}
    check.reply('작성자 A', _api(run, 'POST', '/reports', a['token'], body), 404, REVIEW_GONE)
    check.reply('B 의 매칭 상대 C', _api(run, 'POST', '/reports', c['token'], body), 404, REVIEW_GONE)
    _drop_reports(run, review, check)
    return check.result('"14c · 14d 깃발 0개" 는 API 응답에 신고 표시가 없어 앱 몫')


def rev_39(run):
    check = Check()
    a, b = run.account('basic'), run.account('basic')
    review = _review(run, a, b)
    _patch(run, f'friend_reviews?id=eq.{review}', {'status': 'blinded'})
    body = {'target_type': 'friend_review', 'target_id': review, 'reason': 'spam'}
    check.reply('받은 사람 B', _api(run, 'POST', '/reports', b['token'], body), 404, REVIEW_GONE)
    _drop_reports(run, review, check)
    return check.result()


def rev_40(run):
    check = Check()
    a, b = run.account('basic'), run.account('basic')
    _review(run, a, b)  # 표가 비어 있어서 0행이 나온 것이 아니라는 것을 보이려 한 행을 둔다
    before = _count(run, 'friend_reviews')
    status, body = _as_user(run, a, 'GET', 'friend_reviews?select=id')
    # 0행(200)은 거부가 아니다 — 권한이 아예 없어야 한다(create_friend_reviews.sql: 앱에 grant 없음).
    check.that(status in (401, 403), f'select: {status}(기대 거부 401/403) {body}')
    status, body = _as_user(run, a, 'POST', 'friend_reviews',
                            {'reviewer_id': a['id'], 'reviewee_id': b['id'], 'tags': ['성실해요']})
    check.that(status in (401, 403), f'insert: {status}(기대 거부 401/403) {body}')
    check.that(_count(run, 'friend_reviews') == before, 'friend_reviews 새 행이 생김')
    return check.result()


CASES = {
    'E-CHAT-14': chat_14, 'E-CHAT-21': chat_21, 'E-CHAT-63': chat_63, 'E-CHAT-64': chat_64, 'E-CHAT-70': chat_70,
    'E-CHAT-71': chat_71, 'E-REV-08': rev_08, 'E-REV-09': rev_09, 'E-REV-13': rev_13, 'E-REV-14': rev_14,
    'E-REV-15': rev_15, 'E-REV-28': rev_28, 'E-REV-38': rev_38, 'E-REV-39': rev_39, 'E-REV-40': rev_40,
}
BUNDLES = {'area3-api': list(CASES)}


def attempt(run, case):
    """가설 하나. 준비가 안 되면 blocked."""
    try:
        return CASES[case](run)
    except Blocked as e:
        return 'blocked', str(e)
