"""영역 4 알림함(INBOX) 4개 — E-INBOX-01 · 02 는 폰 한 대(홈 종 → 알림함), E-INBOX-03 · 04 는 API 만.
앱 쪽은 frontend/integration_test/area4_inbox.dart 의 같은 번호. 기대값은 바탕화면 E2E_최종테스트_시나리오.md 영역 4 "4-5. 알림함" 줄이다.

  E-INBOX-01  홈 종 배지 숫자(3) → 종을 누르면 알림함 → 줄 3개(문구 · 최신순) → 첫 줄을 누르면 그 알림의 화면(받은 리뷰) → 돌아오면 배지 2
              + 서버: 눌러 본 줄만 읽음, 안 읽은 수 2
  E-INBOX-02  알림함의 "모두 읽음" → 버튼이 사라지고 → 돌아오면 종 배지가 없다 + 서버: 안 읽은 수 0 · 줄 3개는 그대로(읽음일 뿐 지우지 않는다)
  E-INBOX-03  알림 스위치를 끈 종류도 알림함에는 남는다(10-10 사용자 결정 — 스위치는 푸시만 끈다). 푸시가 안 가는 것은 E-PUSH-13 이 본다
  E-INBOX-04  알림함 API 모양과 읽음 규칙 — `GET /notifications`(items · unread_count · next_before) · `GET /notifications/unread-count` ·
              한 줄 읽음(멱등 · 없는 id 와 남의 id 는 404) · 모두 읽음

알림함 줄은 푸시가 아니라 서버가 알림을 보낼 때 같이 쌓으므로(backend/app/cards/push.py `_record`) 시각(22~08시 조용한 시간)과 상관없이 같은 값이다.
"""

from e2e import area1, area3_phone, tools
from e2e import notify_factory as factory
from e2e.area1 import Check, _api, _app
from e2e.area3_phone import _permitted
from e2e.area4_push import ACCEPT_TITLE, REVIEW_TITLE, accept_body
from e2e.tools import Blocked

CASE_LIMIT = 600
RECEIVED_REVIEWS = '받은 리뷰'  # 지인 리뷰 알림을 누르면 열리는 화면의 앱바 제목(friend_review route)
TITLES = ('알림', RECEIVED_REVIEWS)


def review_body(nickname):
    return f'{nickname} 님이 리뷰를 남겼어요'


def _inbox(run, account):
    """GET /notifications → (상태, 본문)."""
    return _api(run, 'GET', '/notifications', account['token'])


def _seed(run):
    """받는 사람 [me] 에게 알림함 줄 셋 — 대화 신청 둘(p1 → p2 순) · 지인 리뷰 하나(p3, 가장 나중이라 맨 위). 각 사람 닉네임을 정해 둔다."""
    me = area3_phone._person(run)
    people = [area3_phone._person(run) for _ in range(3)]
    for person in people[:2]:
        factory.accept_card(run, person, factory.card(run, person, me))
    factory.link(run, people[2], me)
    factory.review(run, people[2], me)
    return me, people


def want_rows(people):
    """알림함 맨 위부터 (제목, 본문) — 최신순이라 리뷰, p2 의 신청, p1 의 신청."""
    return [(REVIEW_TITLE, review_body(people[2]['nickname'])),
            (ACCEPT_TITLE, accept_body(people[1]['nickname'])),
            (ACCEPT_TITLE, accept_body(people[0]['nickname']))]


def _server_rows(check, run, me, people, label):
    """서버의 알림함이 방금 만든 세 줄(안 읽음 3)인지 — 앱을 켜기 전 준비가 맞는지 본다. 틀리면 준비 실패(blocked)."""
    status, body = _inbox(run, me)
    if status != 200:
        raise Blocked(f'{label} GET /notifications {status}')
    got = [(item['title'], item['body']) for item in body['items']]
    if got != want_rows(people) or body['unread_count'] != 3:
        raise Blocked(f'{label} 알림함 줄 {len(got)}개 · 안 읽음 {body["unread_count"]}(기대 3줄 · 3) — 앱을 켜기 전 준비가 틀림')
    return body


def p_inbox_01(run, phone):
    check = Check()
    me, people = _seed(run)
    _server_rows(check, run, me, people, '준비')
    said = _app(check, phone(token_hash=run.link(me['email'])))
    check.that(said.get('badge') == 3, f"홈 종 배지 {said.get('badge')!r}(기대 3)")
    rows = [tuple(row[:2]) for row in said.get('rows') or []]
    check.that(rows == want_rows(people), f'알림함 줄 {rows}(기대 {want_rows(people)})')
    check.that(said.get('landed') == RECEIVED_REVIEWS, f"첫 줄을 누른 뒤 화면 {said.get('landed')!r}(기대 {RECEIVED_REVIEWS!r})")
    check.that(said.get('badge_after') == 2, f"돌아온 홈 종 배지 {said.get('badge_after')!r}(기대 2)")
    status, body = _inbox(run, me)
    check.that(status == 200, f'앱 뒤 GET /notifications {status}')
    if status == 200:
        flags = [item['read'] for item in body['items']]
        check.that(flags == [True, False, False], f'읽음 표시 {flags}(기대 [True, False, False] — 누른 줄만 읽음)')
        check.that(body['unread_count'] == 2, f"서버 안 읽은 수 {body['unread_count']}(기대 2)")
    return check.result()


def p_inbox_02(run, phone):
    check = Check()
    me, people = _seed(run)
    _server_rows(check, run, me, people, '준비')
    said = _app(check, phone(token_hash=run.link(me['email'])))
    check.that(said.get('badge') == 3, f"홈 종 배지 {said.get('badge')!r}(기대 3)")
    check.that(said.get('button_gone') is True, f"모두 읽음 뒤 \"모두 읽음\" 버튼이 사라짐 {said.get('button_gone')!r}(기대 True)")
    check.that(said.get('rows_after') == 3, f"모두 읽음 뒤에도 줄 {said.get('rows_after')!r}개(기대 3 — 지우지 않는다)")
    check.that(said.get('badge_after') == 0, f"돌아온 홈 종 배지 {said.get('badge_after')!r}(기대 0 — 배지 없음)")
    status, body = _inbox(run, me)
    check.that(status == 200, f'앱 뒤 GET /notifications {status}')
    if status == 200:
        check.that(len(body['items']) == 3 and all(item['read'] for item in body['items']),
                   f"읽음 표시 {[item['read'] for item in body['items']]}(기대 줄 3개 모두 True)")
        check.that(body['unread_count'] == 0, f"서버 안 읽은 수 {body['unread_count']}(기대 0)")
    return check.result()


def inbox_03(run):
    """스위치 "대화 신청"(acceptance_received)을 끄고 신청 받음 → 알림함에 chat_request 한 줄(안 읽음) → 다시 켜고 한 건 더 → 두 줄."""
    check = Check()
    me, partner, partner2 = (area3_phone._person(run) for _ in range(3))
    factory.switches(run, me, acceptance_received=False)
    factory.accept_card(run, partner, factory.card(run, partner, me))
    status, body = _inbox(run, me)
    check.that(status == 200, f'GET /notifications {status}')
    if status == 200:
        got = [(item['kind'], item['read']) for item in body['items']]
        check.that(got == [('chat_request', False)], f'스위치를 끈 채 신청을 받은 뒤 알림함 {got}(기대 [("chat_request", False)])')
        check.that(body['unread_count'] == 1, f"안 읽은 수 {body['unread_count']}(기대 1)")
    factory.switches(run, me, acceptance_received=True)
    factory.accept_card(run, partner2, factory.card(run, partner2, me))
    status, body = _inbox(run, me)
    if status == 200:
        got = [item['kind'] for item in body['items']]
        check.that(got == ['chat_request', 'chat_request'], f'스위치를 다시 켜고 한 건 더 받은 뒤 알림함 {got}(기대 두 줄)')
    return check.result('푸시가 안 가는 것은 E-PUSH-13 이 본다')


def inbox_04(run):
    """알림함 API 모양 · 읽음 규칙(본인 계정 셋 + 남의 계정 하나)."""
    check = Check()
    me, people = _seed(run)
    body = _server_rows(check, run, me, people, '준비')
    check.that(sorted(body) == ['items', 'next_before', 'unread_count'], f'GET /notifications 칸 {sorted(body)}')
    check.that(sorted(body['items'][0]) == ['body', 'created_at', 'data', 'id', 'kind', 'read', 'title'], f"줄 칸 {sorted(body['items'][0])}")
    check.that(body['next_before'] is None, f"next_before {body['next_before']!r}(기대 None — 세 줄이라 다음 쪽 없음)")
    check.reply('안 읽은 수', _api(run, 'GET', '/notifications/unread-count', me['token']), 200)
    status, count = _api(run, 'GET', '/notifications/unread-count', me['token'])
    check.that(count == {'unread_count': 3}, f'unread-count 본문 {count}(기대 3)')
    first, second = body['items'][0]['id'], body['items'][1]['id']
    check.reply('한 줄 읽음', _api(run, 'POST', f'/notifications/{first}/read', me['token']), 200)
    check.reply('같은 줄 다시 읽음(멱등)', _api(run, 'POST', f'/notifications/{first}/read', me['token']), 200)
    status, now = _inbox(run, me)
    check.that(status == 200 and now['unread_count'] == 2, f"한 줄 읽은 뒤 안 읽은 수 {now.get('unread_count') if status == 200 else status}(기대 2)")
    stranger = area3_phone._person(run)
    check.reply('남의 알림 읽음(존재 여부를 알려 주지 않는다)', _api(run, 'POST', f'/notifications/{second}/read', stranger['token']), 404)
    check.reply('없는 알림 읽음', _api(run, 'POST', '/notifications/00000000-0000-4000-8000-000000000000/read', me['token']), 404)
    status, now = _inbox(run, me)
    check.that(status == 200 and now['unread_count'] == 2, '남의 계정이 읽음을 시도한 뒤 내 안 읽은 수가 바뀜')
    check.reply('모두 읽음', _api(run, 'POST', '/notifications/read-all', me['token']), 200)
    status, now = _inbox(run, me)
    check.that(status == 200 and now['unread_count'] == 0 and len(now['items']) == 3 and all(i['read'] for i in now['items']),
               '모두 읽음 뒤 줄 3개 모두 읽음 · 안 읽은 수 0 이어야 함')
    return check.result()


PHONE = {'E-INBOX-01': _permitted(p_inbox_01), 'E-INBOX-02': _permitted(p_inbox_02)}
CASES = {'E-INBOX-03': inbox_03, 'E-INBOX-04': inbox_04}

area1.PHONE.update(PHONE)
area1.CASES.update(CASES)
tools.CASE_LIMITS.update({case: CASE_LIMIT for case in PHONE})
area1.BUNDLES['area4-inbox'] = list(PHONE)
area1.BUNDLES['area4-inbox-api'] = list(CASES)
