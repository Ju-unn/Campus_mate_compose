"""알림 공장 — 알림 시험의 앞 상태를 만들고 "상대 쪽 행동" 을 API 로 대신한다(영역 4 PUSH).

받는 사람만 폰에 두고 보내는 사람은 계정 토큰으로 서버 API 를 부른다. 그래서 두 번째 기기가 없어도 된다.
카드 · 매칭 · 추천 연결 · 리뷰 · 메시지의 준비는 영역 2 · 3 의 같은 이름 도우미를 그대로 쓴다(앞에 `_` 가 붙은 것을 여기서 한 번만 감싼다).
이번 실행이 만든 계정만 만진다(`area2._guard`). tools.py 는 건드리지 않는다.
"""
from e2e import area2, area3, tools
from e2e.area1 import _api
from e2e.tools import Blocked

SWITCHES = ('card_arrived', 'acceptance_received', 'match_made', 'new_message', 'trust_reminder',
            'new_friend_review', 'marketing', 'quiet_hours')


def pair(run):
    """(받는 사람, 보내는 사람) — 둘 다 홈 계정(온보딩 끝 · 활성). 정지 · 탈퇴만 알림을 막으니 받는 쪽도 활성이어야 비교가 된다."""
    return run.account('home'), run.account('home')


def _own(run, *accounts):
    area2._guard(run, *(a['id'] for a in accounts))


def _ok(reply, label, *statuses):
    got, body = reply
    if got not in (statuses or (200,)):
        raise Blocked(f'{label} {got} {body}')
    return body


def card(run, owner, target):
    """살아 있는 카드 한 장(owner → target). 카드 도착 알림은 배치만 만들어서, 이 카드는 수락 쪽 시험용이다."""
    _own(run, owner, target)
    return area2._card(run, owner, target)


def accept_card(run, owner, card_id):
    """owner 가 카드를 수락 — 받는 쪽에 "나를 수락한 사람이 있어요" 가 간다."""
    _ok(_api(run, 'POST', f'/cards/{card_id}/decision', owner['token'], {'decision': 'accept'}), '카드 수락')


def reject_card(run, owner, card_id):
    _ok(_api(run, 'POST', f'/cards/{card_id}/decision', owner['token'], {'decision': 'reject'}), '카드 거절')


def accept_back(run, target, card_id):
    """받은 수락을 target 이 수락 → 매칭이 만들어지고 양쪽에 알림."""
    _ok(_api(run, 'POST', f'/cards/acceptances/{card_id}', target['token'], {'decision': 'accept'}), '받은 수락 수락')


def match(run, x, y):
    """두 계정의 매칭을 DB 로 만든다. 알림은 가지 않는다(서버 API 를 안 지난다) — 메시지 · 신뢰 시험의 앞 상태."""
    _own(run, x, y)
    return area3._match(run, x, y)


def send(run, sender, match_id, body='안녕하세요'):
    _ok(area3._send(run, sender, match_id, body), '메시지 보내기', 201)


def trust(run, account, match_id):
    """신뢰 확인 수락."""
    _ok(_api(run, 'POST', f'/chat/matches/{match_id}/trust', account['token']), '신뢰 수락')


def link(run, referrer, referee):
    """추천 연결(지인 리뷰를 쓸 수 있는 사이)."""
    _own(run, referrer, referee)
    area3._link(run, referrer, referee)


def review(run, reviewer, reviewee):
    _ok(area3._review_post(run, reviewer, reviewee), '지인 리뷰', 201)


def redeem(run, account, code):
    """추천 코드 입력 — 코드 주인에게 "친구가 가입했어요"."""
    _ok(_api(run, 'POST', '/referral/redeem', account['token'], {'code': code}), '추천 코드 입력')


def switches(run, account, **values):
    """알림 스위치를 서버 API 로 바꾼다(앱 16d 와 같은 길). 모르는 이름은 막는다."""
    unknown = set(values) - set(SWITCHES)
    if unknown:
        raise ValueError(f'모르는 알림 스위치: {sorted(unknown)}')
    _ok(_api(run, 'PATCH', '/cards/notification-settings', account['token'], values), '알림 스위치')


def default_switches(run, account):
    """스위치 행을 지워 기본값으로(= [기본]). 이번 실행이 만든 계정만."""
    _own(run, account)
    status, body = tools.rest(run.cfg, run.key, 'DELETE', f"notification_settings?profile_id=eq.{account['id']}")
    if status >= 300:
        raise Blocked(f'알림 스위치 지우기 {status} {body}')
