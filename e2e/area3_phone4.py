"""영역 3 폰 A 한 대 4차 — 매칭 시각(matches.created_at)만 과거로 옮긴 방의 14f 신뢰 확인 시트 6개(묶음 area3-phone-4).
기대값은 바탕화면 E2E_최종테스트_시나리오.md 영역 3 의 그 줄이다(10-04 갱신본). 앱 쪽은 frontend/integration_test/area3_b4.dart 의 같은 번호.
배치([배치] chat-gate)를 부르는 50~55 · 57 · 65~67 · 69 와 밤에만 되는 34 · 42 는 이 묶음이 아니다 — 운영 배치는 부르지 않는다.

가설 하나 = 함수 하나 `(run, phone) -> (결과, 메모)`. PC 가 폰 계정(홈까지) · 상대 · 매칭을 만들고 DB 의 created_at 만 옮긴 뒤 앱을 켜면, 앱이
방을 열어 화면에서 본 것(시트 · 아이디 · 남은 시간 · 배너 · 오류 문구)만 말하고 판정은 여기서 한다. 시간은 PC 가 옮기는 DB 시각뿐이다 — 에뮬 · 폰
시계는 건드리지 않는다.

시나리오와 다르게 도는 것(보고의 "확인 필요"):
  E-CHAT-45  "남은 시간 약 23:59:00(±1분)" 은 방을 여는 데 걸린 만큼 줄어든 값이라, 리터럴 23:59:00 이 아니라 PC 가 옮긴 created_at + 48시간 −
             앱이 말한 시트 표시 시각(앱 시계)을 기대로 삼고 ±1분을 그 값에 건다. 시계 오차가 있어도 앱 시계끼리 비교한다.
  E-CHAT-46  "시트 아래로 밀어 닫기" 는 제목 글자를 잡고 한 번 밀고, 안 닫히면 시트 맨 위(손잡이 줄)를 잡고 한 번 더 민다 — 둘째 밀기에서
             닫히면 메모에 남는다. "다시 방 열기" 는 대화 목록에서 그 줄을 다시 눌러서다.
  E-CHAT-47  "방 열고 90초 기다리기, 60초 ± 5초 뒤" — 앱이 로그인을 마치고 대화 목록에서 그 방 줄을 찾은 채 멈추면(step) 그때 PC 가 created_at 을
             지금 − 23시간 59분으로 옮기고, 앱이 줄을 눌러 방을 연다. 그러니 경계(created_at + 24시간)는 방을 연 1~3초 뒤에서 60초 안쪽이다. 판정은
             "시트가 방을 연 뒤 (created_at + 24시간 − 방 연 시각)초 ± 5초에 뜬다" — 리터럴 60초가 아니라 타이머가 맞춰야 하는 경계다. 방을 연 순간
             이미 시트가 떠 있으면 실패(경계가 이미 지난 방).
  E-CHAT-49  시나리오는 "둘다"(B에뮬)인데 폰 한 대로 돈다 — 상대 쪽 "나감 줄" 은 DB messages 의 kind=left 한 줄로 본다.
  E-CHAT-56  "수락" 은 배너가 아니라 시트의 "수락하고 공유하기" 다 — 48시간 지난 방은 24시간이 지난 방이라 시트 단계이고, 시트는 확인 창이 없다.
             앱은 오류 줄이 처음 뜬 문구를 말한다(시트가 닫히며 dismissSheet 가 오류 줄을 지울 수 있다 — 끝 값이 달라지면 메모에 남는다).
"""

import re
import secrets
from datetime import datetime, timedelta, timezone

from e2e import area1, area3
from e2e.area1 import Check, _app, _one
from e2e.area3 import _patch
from e2e.area3_phone import MISSING, _left_line, _permitted
from e2e.area3_phone2 import _room, _sent
from e2e.tools import Blocked

DAY = timedelta(hours=24)
SHEET_AGE = timedelta(hours=24, minutes=1)  # 시트 단계(24시간 지남)이고 48시간 안이라 아직 수락할 수 있다
EDGE_AGE = timedelta(hours=23, minutes=59)  # 24시간 경계가 60초 앞
DEAD_AGE = timedelta(hours=48, minutes=1)  # 응답 기한(48시간)이 지났는데 배치는 아직 안 돌았다
COUNTDOWN_TOLERANCE = 60  # 시나리오 ±1분(초)
BOUNDARY_TOLERANCE = 5  # 시나리오 ±5초
BOUNDARY_WAIT = 90  # 앱이 시트를 기다리는 초(chat_room_screen.dart 타이머 + 여유)
ENDING = '이 대화는 23시간 뒤 종료돼요'  # chat_room_screen.dart:404 · 방 나이 24시간 1분이면 남은 시간 23:5x → coarseRemainingLabel 23시간
GATE_OVER = '응답 기한이 지나 이 대화는 종료됐어요'  # chat_errors.dart:11


def _at(text):
    """앱이 말한 시각(Dart toUtc().toIso8601String()) — 못 읽으면 None."""
    try:
        at = datetime.fromisoformat(text.replace('Z', '+00:00'))
    except (AttributeError, ValueError):
        return None
    return at if at.tzinfo else at.replace(tzinfo=timezone.utc)


def _seconds(text):
    """시트 카운트다운 글자 "23:58:41" → 초. 못 읽으면 None."""
    found = re.fullmatch(r'(\d+):(\d{2}):(\d{2})', text) if isinstance(text, str) else None
    return int(found[1]) * 3600 + int(found[2]) * 60 + int(found[3]) if found else None


def _label(seconds):
    seconds = max(0, int(seconds))
    return f'{seconds // 3600:02d}:{seconds % 3600 // 60:02d}:{seconds % 60:02d}'


def _move(run, match_id, age):
    """매칭의 created_at 을 지금 − [age] 로 — DB 시각만 옮긴다. 옮긴 시각을 돌려준다."""
    created = datetime.now(timezone.utc) - age
    _patch(run, f'matches?id=eq.{match_id}', {'created_at': created.isoformat()})
    return created


def _aged(run, age):
    """(폰 계정, 토큰, 상대, 매칭 id, created_at) — 방금 만든 방의 created_at 을 [age] 만큼 과거로 옮겼다."""
    me, token, partner, match_id = _room(run)
    return me, token, partner, match_id, _move(run, match_id, age)


def _kakao(run, account):
    return _one(run, f"profile_private?profile_id=eq.{account['id']}&select=kakao_id").get('kakao_id')


def _side(run, match_id, account):
    return _one(run, f"match_participants?match_id=eq.{match_id}&profile_id=eq.{account['id']}&select=trust_response,left_at")


def _sheet_up(check, said):
    check.that(said.get('sheet') is True, f"14f 시트 {said.get('sheet', MISSING)}(기대 True)")


def _no_accept(run, check, me, match_id):
    accepts = _sent(run, me, match_id, 'trust_accept')
    check.that(not accepts, f'수락 줄 {len(accepts)}개(기대 0)')


def p_chat_45(run, phone):
    check = Check()
    me, token, partner, match_id, created = _aged(run, SHEET_AGE)
    said = _app(check, phone(token_hash=token, nickname=partner['nickname']))
    _sheet_up(check, said)
    kakao = _kakao(run, me)
    check.that(said.get('sheet_id') == kakao, f"시트 아이디 {said.get('sheet_id', MISSING)!r}(기대 DB 값 {kakao!r})")
    shown, seconds = _at(said.get('shown_at')), _seconds(said.get('countdown'))
    if shown is None or seconds is None:
        check.problems.append(f"남은 시간 {said.get('countdown', MISSING)!r} · 표시 시각 {said.get('shown_at', MISSING)!r} 를 못 읽음")
    else:
        want = (created + 2 * DAY - shown).total_seconds()
        check.that(abs(seconds - want) <= COUNTDOWN_TOLERANCE,
                   f"남은 시간 {said['countdown']}(기대 {_label(want)} ±{COUNTDOWN_TOLERANCE}초 — 앱이 시트를 연 시각 기준)")
    return check.result()


def p_chat_46(run, phone):
    check = Check()
    me, token, partner, match_id, _ = _aged(run, SHEET_AGE)
    said = _app(check, phone(token_hash=token, nickname=partner['nickname']))
    _sheet_up(check, said)
    swipes = said.get('swipes', MISSING)
    check.that(swipes in (1, 2), f'아래로 밀어도 시트가 안 닫힘(닫힌 밀기 {swipes!r}번째, 기대 1~2)')
    check.that(said.get('banners') == [ENDING], f"배너 {said.get('banners', MISSING)}(기대 [{ENDING}])")
    check.that(said.get('again') is True, f"다시 들어오면 시트 {said.get('again', MISSING)}(기대 True)")
    _no_accept(run, check, me, match_id)  # 밀어 닫기는 수락이 아니다
    return check.result(f'{swipes}번째 밀기(손잡이를 잡고 다시)에서 닫힘' if swipes == 2 else '')


def p_chat_47(run, phone):
    check = Check()
    me, token, partner, match_id = _room(run)
    moved = []

    def move(said):  # 앱이 목록에서 그 방 줄을 찾고 멈춘 사이 — 방을 열기 직전에 옮겨야 경계가 방을 연 때부터 60초 안쪽이다
        moved.append(_move(run, match_id, EDGE_AGE))

    said = _app(check, phone(midway=move, token_hash=token, nickname=partner['nickname']))
    if not moved:
        check.problems.append('앱이 방 줄을 찾고 멈추지 않아(step) 방 시각을 못 옮김')
        return check.result()
    check.that(said.get('sheet_at_open') is False, f"방을 연 순간 시트가 이미 떠 있었음 {said.get('sheet_at_open', MISSING)}(경계가 이미 지난 방)")
    ms, opened = said.get('sheet_ms'), _at(said.get('open_at'))
    if said.get('sheet') is not True or not isinstance(ms, (int, float)):
        check.problems.append(f"{BOUNDARY_WAIT}초 안에 시트가 안 뜸(sheet {said.get('sheet', MISSING)}, sheet_ms {ms!r})")
        return check.result()
    if opened is None:
        check.problems.append(f"방을 연 시각 {said.get('open_at', MISSING)!r} 를 못 읽음")
        return check.result()
    after, want = ms / 1000, (moved[0] + DAY - opened).total_seconds()
    check.that(abs(after - want) <= BOUNDARY_TOLERANCE,
               f'시트가 방을 연 뒤 {after:.1f}초에 뜸(기대 경계 {want:.1f}초 ±{BOUNDARY_TOLERANCE}초)')
    return check.result(f'방을 연 뒤 {after:.1f}초에 시트(시나리오 60초 ± 5초, 경계까지 {want:.1f}초)')


def p_chat_48(run, phone):
    check = Check()
    me, token, partner, match_id, _ = _aged(run, SHEET_AGE)
    before = _kakao(run, me)
    if not before:
        raise Blocked('폰 계정 profile_private.kakao_id 가 비어 있음 — 시트에 보일 아이디가 없다')
    value = f"e2e{me['n']}c{secrets.token_hex(3)}"  # 앱 16e-1 은 비어 있지만 않으면 저장한다(형식 제약 없음) — 영문 · 숫자만
    said = _app(check, phone(token_hash=token, nickname=partner['nickname'], kakao=before, value=value))
    check.that(said.get('sheet_before') == before, f"시트 아이디(변경 전) {said.get('sheet_before', MISSING)!r}(기대 DB 값 {before!r})")
    check.that(said.get('sheet_after') == value, f"시트 아이디(돌아온 뒤) {said.get('sheet_after', MISSING)!r}(기대 새 값 {value!r})")
    got = _kakao(run, me)
    check.that(got == value, f'profile_private.kakao_id {got!r}(기대 새 값 {value!r})')
    return check.result()


def p_chat_49(run, phone):
    check = Check()
    me, token, partner, match_id, _ = _aged(run, SHEET_AGE)
    said = _app(check, phone(token_hash=token, nickname=partner['nickname']))
    _sheet_up(check, said)
    check.that(said.get('confirm') is True, f"나가기 확인 창 {said.get('confirm', MISSING)}(기대 True)")
    check.that(said.get('row_gone') is True, f"내 대화 목록에서 방이 사라짐 {said.get('row_gone', MISSING)}(기대 True)")
    mine, theirs = _side(run, match_id, me), _side(run, match_id, partner)
    check.that(mine.get('trust_response') is None, f"trust_response {mine.get('trust_response')!r}(기대 null 그대로)")
    check.that(bool(mine.get('left_at')), f"left_at {mine.get('left_at')!r}(기대 채워짐)")
    check.that(not theirs.get('left_at'), f"상대 left_at {theirs.get('left_at')!r}(기대 비어 있음 — 나간 사람은 폰 계정뿐)")
    lines, want = _sent(run, me, match_id, 'left'), _left_line(me)
    check.that(lines == [want], f'상대가 보는 나감 줄 {lines}(기대 [{want!r}] 한 줄)')
    _no_accept(run, check, me, match_id)  # "거절하고 나가기" 는 수락이 아니다
    return check.result()


def p_chat_56(run, phone):
    check = Check()
    me, token, partner, match_id, _ = _aged(run, DEAD_AGE)
    said = _app(check, phone(token_hash=token, nickname=partner['nickname']))
    _sheet_up(check, said)  # 시트의 "수락하고 공유하기" 를 눌러야 서버로 수락 요청이 나간다
    error = said.get('error', MISSING)
    check.that(error == GATE_OVER, f'오류 문구 {error!r}(기대 {GATE_OVER!r})')
    mine = _side(run, match_id, me)
    check.that(mine.get('trust_response') is None, f"trust_response {mine.get('trust_response')!r}(기대 null 그대로)")
    _no_accept(run, check, me, match_id)
    passed = _one(run, f'matches?id=eq.{match_id}&select=trust_passed_at').get('trust_passed_at')
    check.that(not passed, f'trust_passed_at {passed!r}(기대 null)')
    gone = error == GATE_OVER and said.get('error_now') != error
    return check.result(f"오류 줄 끝 값 {said.get('error_now', MISSING)!r} — 처음 뜬 뒤 사라짐(dismissSheet 의 copyWith 가 오류 줄을 지움, 결함 후보 낮음)"
                        if gone else '')


PHONE4 = {'E-CHAT-45': p_chat_45, 'E-CHAT-46': p_chat_46, 'E-CHAT-47': p_chat_47, 'E-CHAT-48': p_chat_48,
          'E-CHAT-49': p_chat_49, 'E-CHAT-56': p_chat_56}
PHONE4 = {name: _permitted(case) for name, case in PHONE4.items()}

area1.PHONE.update(PHONE4)
area3.BUNDLES['area3-phone-4'] = list(PHONE4)
