"""영역 4 PUSH 카드 배치 9개(E-PUSH-01~09, 묶음 area4-push-card) — 카드 배치(daily-cards)가 돌 때 알림이 오는지 · 안 오는지.
기대값은 바탕화면 E2E_최종테스트_시나리오.md 영역 4 의 E-PUSH 줄(10-04 갱신본), 분류는 E2E_결과/영역갱신/push_분류표.md. 코드가 다르면 코드가 기준이다
(backend/app/cards/issuing.py · push.py). 앱 쪽은 frontend/integration_test/area4_push_card.dart(03 만 새로, 나머지는 있는 가설의 별칭).

배치는 **언제나 `area2._batch` 로** — 월요일 종일 · 00:00~07:10 이면 gcloud 를 안 부르고 blocked 다. 가설은 시작에서 `td.require_daily_cards_open()` 로
계정 · 앱 · 권한을 만들기 전에 막는다(E-PUSH-06 은 밤 22:00~23:59, 월요일 제외). 서버 전체에 도는 호출이라 가설당 횟수를 최소로 한다(01 · 04 · 05 · 06 · 02 · 03 · 09 는
1번, 07 · 08 은 2번). 카드 도착 알림은 방해 금지 예외(push.py `_QUIET_HOURS_EXEMPT`)라 밤에도 온다.

  기존 가설에 맡김   01 = area2_time_device.p_card_01 · 04 = p_card_03 · 05 = p_card_18 · 06 = p_card_17(fail 이면 다시 안 돎 — 밤 창이라 둘째 시도가 자정을 넘긴다) (일감 번호는 phone() 이 E-PUSH-xx 로 싣는다)
  새로 쓴 것         02(p_card_02 에 훅) · 03(꺼진 앱) · 07(일시중지) · 08(두 번) · 09(후보 0명)

시나리오와 다르게 도는 것(보고의 "확인 필요"):
  B에뮬 → 폰 한 대   시나리오는 B에뮬이지만 구현은 지금 연결된 기기(--device A)에서 돈다. 폰 계정이 받는 사람 A 이고 상대 B · 대조군은 DB 로 만든다.
  01 · 05 · 06      시나리오는 "배치 부르기" 만 — 구현은 같은 성별 대조군을 하나 더 두어 대조군이 카드를 받아야 "배치가 돌았다" 고 본다(없으면 blocked).
  02                "알림 목록에서 그 알림이 사라짐" 은 눌러 도착한 알림의 key 로 본다(같은 글의 옛 알림 때문에 거짓 fail 이 나지 않게). 권한을 빼기 전에 읽는다 —
                    p_card_02 끝에서 알림 권한을 빼는데, 빼면 이미 뜬 알림이 지워질 수 있어 그 뒤에 읽으면 거짓 통과다.
  03                "앱이 켜진 뒤 10초 안" 은 알림 누름 → 앱 부팅 → 로그인 · 관문 조회 → 오늘 탭까지라 10초가 빠듯하다. 앱이 말한 ms(일감 받은 뒤부터)를 메모에 남기고
                    30초 안이면 pass, 10초를 넘으면 메모에 경고("확인 필요")를 단다. 오늘 탭을 놓쳐 약관 · 홈에 머물면(A10 회귀) fail 이고 메모에 그때 본 화면 이름이 남는다.
  04                p_card_03 그대로 — 앱이 오늘 탭을 앞에 둔 채 배치, 카드가 새로 고침 없이 1장 나타나고(앱이 판정) 알림창 새 알림 0(NOTICE_WAIT 30초).
  06                서버 시계를 못 옮기므로 22:00~23:59 에만 돈다(창 밖이면 "22:00 에 다시").
  07                시나리오의 B 가 폰 계정이다. 일시중지(matching_paused)는 이번 실행 계정에만 건다. 풀고 두 번째 배치로 카드 1 · 알림 1 이 오는 것까지 봐서
                    "안 온다" 가 읽기가 깨진 탓이 아님을 보인다.
  08                두 번째 배치가 돌았다는 증거 — 설정 행의 issue_weekdays 에 사다리가 못 내는 값(SENTINEL)을 심어 두면 배치가 새로 적는다(area2_time_batch 와 같은 앵커).
                    증거가 없으면 blocked.
  09                시나리오의 "응답 no_candidate 1 이상" 은 스케줄러 호출이라 못 읽는다 → 대조군 카드 · A 의 /cards/today(빈 카드 + candidate_pool_empty) · 알림 0 으로 대신.

처음 돌릴 때 시각: 01 · 02 · 03 · 04 · 05 · 07 · 08 · 09 는 월요일 아닌 날 07:11 이후(밤 22시 이후에도 된다). 06 은 월요일 아닌 날 22:00~23:59.
"""

import time

from e2e import area1, area2, area2_phone3, area2_time_batch as tb, area2_time_device as td, notify, tools
from e2e.area1 import Check, _api, _app, _at, _patch
from e2e.area2_phone3 import CARD_TITLE, _wait_for, region_set
from e2e.area3_phone5 import _single_shot
from e2e.tools import Blocked

APP_WAIT = 90  # 눌린 앱이 오늘 탭을 찾고 말하기를 기다리는 초(앱 안의 30초 기다림이 끝나도 남는 여유)
SLOW_OPEN_MS = 10_000  # 시나리오 "앱이 켜진 뒤 10초 안" — 넘으면 메모에 경고
MISSING = '(말 없음)'
CASE_LIMIT_SLOW = 900  # 배치 · 60초 지켜보기 · 앱 기다림이 겹쳐 기본 420초를 넘는 가설
SCREEN_LABELS = {'login': '로그인', 'consent': '약관 동의', 'consent-renew': '약관 갱신', '3b': '학생 인증', '3c': '학교 정보',
                 '04-1': '온보딩 기본 정보', 'home': '홈', 'today': '오늘 탭'}  # area4_push_card.dart _cardScreensNow 의 이름
APP_KEYS = ('today', 'cards', 'today_ms', 'screen', 'opened_at')  # 03 의 tap 판에서 앱이 PC 에 말하는 것


def _screens(said):
    return ' · '.join(f'{name}({SCREEN_LABELS.get(name, "?")})' for name in said.get('screen') or []) or '없음'


def _live(run, owner):
    """[owner] 의 아직 안 끝난 무료 카드 — E-PUSH-09 는 후보를 쉬게 하려고 만료된 카드를 넣으므로 행 수가 아니라 이것을 센다."""
    now = area2._now()
    return [row for row in td._daily_rows(run, owner) if _at(row['expires_at']) > now]


def _pause(run, account, paused):
    """matching_paused 를 건다 · 푼다 — 이번 실행이 만든 계정만(_guard)."""
    area2._guard(run, account['id'])
    _patch(run, f"profiles?id=eq.{account['id']}", {'matching_paused': paused})


def _with_phone(run, phone, check, a):
    """폰 계정 A 로 로그인해 홈에 닿고 기기 토큰이 올라온 뒤 알림창을 읽어 두고 HOME 으로 내린다 → 그 알림 목록(앞 알림과 섞이지 않게).
    홈에 못 닿았으면 None — 토큰도 알림도 기대할 수 없으니 배치를 부르지 않는다."""
    _app(check, phone(token_hash=run.link(a['email'])))
    if check.problems:
        return None
    before = td._ready(run, phone, a)
    notify.background(phone.serial)
    return before


# ── 02 · 03 눌러서 열기 ─────────────────────────────────────────────────────────────────────────────

def push_02(run, phone):
    """E-CARD-02 와 같은 절차(홈에서 멈춤 → HOME → 배치 → 알림 → 누르기 → 앱이 오늘 탭 카드 1장) + 누른 뒤 그 알림이 알림 목록에서 사라졌다."""
    td.require_daily_cards_open()

    def gone(check, arrived):
        keys = {n.key for n in arrived}
        left = [n for n in notify.read_notifications(phone.serial) if n.key in keys]
        check.that(not left, f'알림을 눌렀는데 알림 목록에 "{CARD_TITLE}" 가 {len(left)}개 남음')

    return area2_phone3.p_card_02(run, phone, after=gone)


def push_03(run, phone):
    """앱이 꺼진 채 배치 → 알림 1개 → 누르면 앱이 켜지며 오늘 탭(/today)에 카드 1장. 꺼진 앱 콜드 스타트 패턴은 E-CHAT-32(area3_phone3)와 같다."""
    td.require_daily_cards_open()
    notify.ensure_delivery(phone.serial)  # 푸시 연결이 죽은 폰이면 "온다" 는 헛fail, "안 온다" 는 헛통과 — 계정을 만들기 전에 되살린다(또는 blocked)
    check = Check()
    a, b = td._pair(run)
    control = td._control(run, 'male')
    memo = ''
    with td._permitted(phone.serial), td._every_day(run, a):
        _app(check, phone(token_hash=run.link(a['email']), phase='login'))
        if check.problems:  # 홈에 못 닿았으면 토큰도 알림도 기대할 수 없다
            return check.result()
        before = td._ready(run, phone, a)
        notify.kill_app(phone.serial)
        if td._issue(check, run, a, control=control):
            problems = len(check.problems)
            td._one_notice(check, phone.serial, before)
            if len(check.problems) == problems:
                # 누르기 전에 일감을 넣는다 — 알림으로 콜드 스타트한 앱이 e2e_test.dart 의 hear() 로 이것을 가져간다
                phone.hub.tell({'case': phone.case, 'phase': 'tap'})
                notify.tap_notification(phone.serial, CARD_TITLE)
                said = _app(check, phone.hub.result(APP_WAIT))
                if said:
                    check.that(said.get('today') is True, f'오늘 탭(/today)이 안 열림 — 그때 보인 화면 {_screens(said)}')
                    check.that(said.get('cards') == 1, f'오늘 탭에 카드 {said.get("cards", "?")}장(기대 1)')
                    ms = said.get('today_ms')
                    memo = (f"앱이 오늘 탭을 연 시각 {said.get('opened_at', MISSING)}(앱 시계), 일감 받은 뒤 {ms if ms is not None else MISSING}ms"
                            f" — 앱 부팅 시간 포함")
                    if isinstance(ms, int) and ms > SLOW_OPEN_MS:
                        memo += f' · 시나리오는 10초인데 {ms / 1000:.0f}초 걸림 — 확인 필요(앱 부팅이 느린 것인지)'
    check.that(len(td._daily_rows(run, a)) == 1, f'A 카드가 {len(td._daily_rows(run, a))}장(기대 1)')
    return check.result(memo)


# ── 07 · 08 · 09 배치가 알림을 안 보내는 경우 ─────────────────────────────────────────────────────────

def push_07(run, phone):
    """일시중지한 A: 배치 → 카드 0 · 알림 0 / 풀고 배치 → 카드 1 · 알림 1. 같은 배치를 받은 대조군이 카드를 받아야 "배치가 돌았다" 를 말할 수 있다."""
    td.require_daily_cards_open()
    notify.ensure_delivery(phone.serial)  # 푸시 연결이 죽은 폰이면 "온다" 는 헛fail, "안 온다" 는 헛통과 — 계정을 만들기 전에 되살린다(또는 blocked)
    check = Check()
    a, b = td._pair(run)
    control = td._control(run, 'male')
    with td._permitted(phone.serial), td._every_day(run, a):
        before = _with_phone(run, phone, check, a)  # 일시중지 전에 로그인해 기기 토큰을 올려 둔다
        if before is None:
            return check.result()
        _pause(run, a, True)
        try:
            area2._batch('daily-cards')
            if not _wait_for(lambda: td._daily_rows(run, control), td.CARD_WAIT):
                raise Blocked(f'대조군이 {td.CARD_WAIT}초 안에 카드를 못 받음 — 배치가 안 돈 것 같아 일시중지한 계정이 카드를 안 받았다고 말할 수 없다')
            check.that(not td._daily_rows(run, a), '일시중지한 A 가 카드를 받음')
            seen = notify.expect_none(phone.serial, before, seconds=td.ABSENCE_WAIT)
            check.that(not seen, f'일시중지한 A 에게 새 알림 {len(seen)}건: {[n.title for n in seen]}')
        finally:
            _pause(run, a, False)
        if td._issue(check, run, a, anchored=True):  # 1회차에 대조군이 같은 배치로 카드를 받았다 — 배치는 돈다
            td._one_notice(check, phone.serial, before)
    check.that(len(td._daily_rows(run, a)) == 1, f'일시중지를 푼 뒤 A 카드가 {len(td._daily_rows(run, a))}장(기대 1)')
    return check.result()


def push_08(run, phone):
    """같은 날 배치를 두 번 → A 카드 1장 · 알림 1건. 둘째 배치가 돌았다는 증거(설정 행 요일이 새로 적힘)가 없으면 blocked."""
    td.require_daily_cards_open()
    notify.ensure_delivery(phone.serial)  # 푸시 연결이 죽은 폰이면 "온다" 는 헛fail, "안 온다" 는 헛통과 — 계정을 만들기 전에 되살린다(또는 blocked)
    check = Check()
    a, b = td._pair(run)
    control = td._control(run, 'male')
    region = td._region_of(run, a)
    with td._permitted(phone.serial), td._every_day(run, a):
        before = _with_phone(run, phone, check, a)
        if before is None:
            return check.result()
        if td._issue(check, run, a, control=control):
            td._one_notice(check, phone.serial, before)
            if not check.problems:  # 첫 배치부터 어긋났으면 운영 배치를 한 번 더 부르지 않는다
                shown = notify.read_notifications(phone.serial)  # 첫 알림까지 본 목록 — 둘째 배치 뒤에는 이 뒤에 생긴 것만 본다
                with region_set(run, region, issue_weekdays=tb.SENTINEL):  # 심어 둔 값이 사다리 값으로 바뀌면 둘째 배치가 돈 것
                    area2._batch('daily-cards')
                    if not _wait_for(lambda: tb._saved(run, region) != tb.SENTINEL, tb.FIRST_BATCH_WAIT):
                        raise Blocked(f'둘째 배치를 불렀지만 {tb.FIRST_BATCH_WAIT}초 안에 설정 행의 요일이 안 바뀜 — 배치가 안 돌았거나 실패(이 뒤의 "카드 그대로" 는 믿을 수 없음)')
                time.sleep(area2.SETTLE_SECONDS)  # 설정을 새로 적는 것은 배치의 앞쪽이다 — 카드 돌리기가 끝나기를
                seen = notify.expect_none(phone.serial, shown, seconds=td.ABSENCE_WAIT)
                check.that(not seen, f'같은 날 두 번째 배치 뒤 새 알림 {len(seen)}건: {[n.title for n in seen]}')
    cards = len(td._daily_rows(run, a))
    check.that(cards == 1, f'A 카드가 {cards}장(기대 1)')
    others = len(td._daily_rows(run, control))
    check.that(others <= 1, f'대조군 카드가 {others}장(기대 1)')
    return check.result('' if others else '대조군은 카드를 못 받음 — 대조군 쪽 비교는 못 함')


def push_09(run, phone):
    """A 의 후보를 전부 쉬게 한 뒤 배치 → 카드 0 · 알림 0 · /cards/today 가 빈 카드 + 후보 없음. 대조군이 카드를 받아야 배치가 돈 것이다."""
    td.require_daily_cards_open()
    notify.ensure_delivery(phone.serial)  # 푸시 연결이 죽은 폰이면 "온다" 는 헛fail, "안 온다" 는 헛통과 — 계정을 만들기 전에 되살린다(또는 blocked)
    check = Check()
    a, b = td._pair(run)
    control = td._control(run, 'male')
    with td._permitted(phone.serial), td._every_day(run, a):
        before = _with_phone(run, phone, check, a)
        if before is None:
            return check.result()
        td._rest_pool(run, a)
        area2._batch('daily-cards')
        if not _wait_for(lambda: td._daily_rows(run, control), td.CARD_WAIT):
            raise Blocked(f'대조군이 {td.CARD_WAIT}초 안에 카드를 못 받음 — 배치가 안 돈 것 같아 "카드가 안 나갔다" 를 말할 수 없다')
        check.that(not _live(run, a), f'후보가 없는데 A 가 카드를 받음({len(_live(run, a))}장)')
        today = _api(run, 'GET', '/cards/today', a['token'])
        ok = today[0] == 200 and not today[1].get('cards') and today[1].get('candidate_pool_empty') is True
        check.that(ok, f'A 의 /cards/today 가 빈 카드 + 후보 없음이 아님: {today[0]} {today[1]}')
        seen = notify.expect_none(phone.serial, before, seconds=td.ABSENCE_WAIT)
        check.that(not seen, f'후보가 없는데 새 알림 {len(seen)}건: {[n.title for n in seen]}')
    return check.result('응답의 no_candidate 수치는 스케줄러 호출이라 못 읽음 — 대조군 카드 · /cards/today · 알림창으로 확인. '
                        '카드가 없으면 알림도 없어서 "알림 0" 은 알림 길 생존 증거가 아니다 — 판정의 근거는 카드 0')


PHONE = {
    'E-PUSH-01': td.p_card_01, 'E-PUSH-02': push_02, 'E-PUSH-03': push_03, 'E-PUSH-04': td.p_card_03, 'E-PUSH-05': td.p_card_18,
    'E-PUSH-06': _single_shot(td.p_card_17, always=True), 'E-PUSH-07': push_07, 'E-PUSH-08': push_08, 'E-PUSH-09': push_09,
}

tools.CASE_LIMITS.update({case: CASE_LIMIT_SLOW for case in ('E-PUSH-02', 'E-PUSH-03', 'E-PUSH-04', 'E-PUSH-07', 'E-PUSH-08', 'E-PUSH-09')})

area1.PHONE.update(PHONE)
area1.BUNDLES['area4-push-card'] = list(PHONE)
