"""영역 5 시간조작 2개(묶음 area5-time) — E-WD-10(게이트 미통과 방에서 한쪽 탈퇴 → 48시간이 지나도 chat-gate 가 안 닫음) ·
E-WD-11(탈퇴 30일 뒤 정리 배치가 파일 · auth 사용자 · 딸린 행을 지움). 기대값은 바탕화면 E2E_시나리오_조각/5_나탭_탈퇴_경계.md 5-2 표의 그 줄을
지금 코드와 대조한 것이다. 앱 쪽은 frontend/integration_test/area5_time.dart 의 같은 번호(area5.dart 가 묶는다).

가설 하나 = 함수 하나 `(run, phone) -> (결과, 메모)`. 폰 계정은 늘 남는 쪽 B 이고, 탈퇴하는 A 는 PC 가 API 로 한 번(area5_wd._withdraw_once) 보낸다 —
영역 3 배치 가설(area3_phone5)과 같은 모양이다. 운영 배치는 area3_phone5 의 도구로만 부른다: 준비 전에 관문을 기록 없이 보고(_start),
chat-gate 는 관문을 지난 직후 방 시각을 확정해 한 번(_gated_batch — 확인용 방이 닫히는 것이 "배치가 돌았다" 의 증거), cleanup 은 관문 → gcloud 한 번(_batch).
배치를 부른 뒤의 fail 은 다시 안 돈다(_single_shot). 쓰기는 이번 실행이 만든 계정에만(area2._guard).

시나리오와 다르게 도는 것(보고의 "확인 필요"):
  두 기기 → 폰 한 대  시나리오 기기 칸은 "둘다" 지만 A 의 화면은 보지 않는다(A 는 탈퇴해 화면이 02 뿐이다) — A 탈퇴는 API, B 화면은 폰.
  E-WD-10  ⚠ 문서↔코드 다름: spec §2.6 "30일 동안" 문단은 게이트 실패로 닫힌다지만 코드(chat/batch_router.py:29-38 · gate.is_gone)는 한쪽이라도
           나감 · 정지 · 탈퇴면 통째로 건너뛴다 — 코드 기준(chat_closed_at null 그대로)으로 본다. 응답의 closed 개수는 gcloud 가 안 보여 못 읽는다(DB 로 본다).
           "나간 방 안내 + 채팅방 나가기" 는 E-WD-06 과 같은 화면(chat_room_screen.dart _PartnerGoneNotice)을 B 폰이 연다.
  E-WD-11  응답 deleted_accounts · skipped_accounts 는 gcloud 가 안 보여 못 읽는다 — auth 사용자 404(관리자 목록에 없음) · 행 0 · 파일 0 으로 본다.
           A 의 파일은 탈퇴 뒤 버킷 넷에 그림을 한 장씩 넣는다(탈퇴가 student-id-temp 를 비우므로 뒤에 넣는다 — E-WD-12 와 같다).
           B 대화 목록이 그려졌다는 증거로 닫히지 않는 다른 방(control)을 하나 둔다(E-CHAT-55 와 같다).

유료 호출 — 0(계정 공장의 온보딩은 다른 가설과 같고 이 문으로 막지 않는다). 디스코드 — 0줄.
"""

from datetime import datetime, timedelta, timezone

from e2e import area1, tools
from e2e.area1 import Check, _app, _find_user, _rows
from e2e.area2_phone3 import _wait_for
from e2e.area3 import _count, _match, _messages
from e2e.area3_phone import MISSING, _permitted, _person
from e2e.area3_phone5 import BATCH_WAIT, CASE_LIMIT, _batch, _closed, _gated_batch, _list_said, _own, _sentinel, _single_shot, _start
from e2e.area5_act import _write
from e2e.area5_wd import _files, _plant_file, _state, _withdraw_once
from e2e.tools import Blocked

LEFT_NOTICE = '상대가 채팅방을 나가 더 이상 메시지를 보낼 수 없어요.'  # chat_room_screen.dart _PartnerGoneNotice
GATE_AGE = timedelta(hours=49)  # 시나리오 "matches.created_at 을 49시간 전으로" — 48시간 기한(gate.GATE_DEADLINE)을 지남
GONE_AGE = timedelta(days=31)  # 30일(account/batch_router.py WITHDRAWN_RETENTION) 하루 뒤


def _now():
    return datetime.now(timezone.utc)


def _withdrawn(run, account):
    """A 를 API 로 탈퇴시키고 탈퇴 상태인지 다시 읽는다 — 아니면 "탈퇴한 방" 이 증거가 못 된다."""
    _withdraw_once(run, account)
    if _state(run, account).get('status') != 'withdrawn':
        raise Blocked('준비: A 의 탈퇴가 DB 에 안 보인다(status 가 withdrawn 이 아님)')


# ── E-WD-10 게이트 미통과 방 ─────────────────────────────────────────────────────────────────────────

def p_wd_10(run, phone):
    _start()
    check = Check()
    me, partner = _person(run), _person(run)  # me = B(폰, 남는 쪽) · partner = A(탈퇴)
    _own(run, me, partner)
    sentinel = _sentinel(run)
    match_id = _match(run, me, partner)  # 신뢰 확인 미통과(trust_passed_at 없음)
    _messages(run, match_id, partner, 2)
    _withdrawn(run, partner)
    _gated_batch(run, [me, partner], [(match_id, GATE_AGE)], sentinel)
    check.that(not _closed(run, match_id), 'matches.chat_closed_at 이 채워짐 — 탈퇴한 사람이 있는 방을 48시간 기한에 닫음(기대 null, batch_router.py 건너뜀)')
    left = [p for p in _rows(run, f'match_participants?match_id=eq.{match_id}&select=profile_id,left_at') if p.get('left_at')]
    check.that(not left, f'match_participants.left_at 이 찍힘 {len(left)}행(기대 0 — 탈퇴는 나가기가 아니다)')
    said = _app(check, phone(token_hash=run.link(me['email']), nickname=partner['nickname']))
    if said:
        check.that(said.get('room') is True, f"B 가 그 방을 엶 {said.get('room', MISSING)}(기대 True — 목록에 방이 있어야 한다)")
        check.that(said.get('gone_notice') is True, f"입력칸 자리의 \"{LEFT_NOTICE}\" {said.get('gone_notice', MISSING)}(기대 보임)")
        check.that(said.get('leave_button') is True, f"\"채팅방 나가기\" 버튼 {said.get('leave_button', MISSING)}(기대 보임)")
        check.that(said.get('input') is False, f"입력칸 {said.get('input', MISSING)}(기대 없음 — 나간 방은 입력칸을 남기지 않는다)")
    return check.result('⚠ 코드 기준 — spec §2.6 문단(48시간에 닫힘)과 다르다. 응답 closed 개수는 gcloud 라 못 읽고 DB chat_closed_at 으로 봤다')


# ── E-WD-11 30일 정리 ────────────────────────────────────────────────────────────────────────────────

def p_wd_11(run, phone):
    _start(job='cleanup')
    check = Check()
    me, partner, other = _person(run), _person(run), _person(run)  # B(폰) · A(탈퇴) · control(B 목록이 그려졌다는 증거)
    _own(run, me, partner, other)
    match_id = _match(run, me, partner)
    _messages(run, match_id, me, 2)
    _messages(run, match_id, partner, 1)
    _match(run, me, other)
    _withdrawn(run, partner)
    for bucket in tools.BUCKETS:
        _plant_file(run, partner, bucket)
    if not all(_files(run, bucket, partner) for bucket in tools.BUCKETS):
        raise Blocked('준비: 넣은 파일이 안 보이는 버킷이 있다 — "0개가 됐다" 가 증거가 못 된다')
    _write(run, partner, {'withdrawn_at': (_now() - GONE_AGE).isoformat()})
    _batch('cleanup')
    if not _wait_for(lambda: _find_user(run, partner['email']) is None, BATCH_WAIT):
        raise Blocked(f'정리 배치 뒤 {BATCH_WAIT}초가 지나도 31일 전 탈퇴한 A 의 auth 사용자가 남음 — 배치가 안 돌았거나 늦음')
    for bucket in tools.BUCKETS:
        left = _files(run, bucket, partner)
        check.that(not left, f'{bucket}/{{A id}}/ 파일 {len(left)}개(기대 0)')
    for table, path in (('profiles', f"profiles?id=eq.{partner['id']}"), ('profile_private', f"profile_private?profile_id=eq.{partner['id']}"),
                        ('matches', f'matches?id=eq.{match_id}'), ('messages', f'messages?match_id=eq.{match_id}')):
        rows = _count(run, path)
        check.that(rows == 0, f'{table} {rows}행이 남음(기대 0 — 연쇄 삭제)')
    alive = all(_find_user(run, a['email']) is not None for a in (me, other))
    check.that(alive, '남는 B · 대조 계정까지 auth 사용자가 지워짐')
    said = _app(check, phone(token_hash=run.link(me['email']), nickname=partner['nickname'], control=other['nickname']))
    _list_said(check, said, partner['nickname'], present=False)
    return check.result('deleted_accounts · skipped_accounts 는 gcloud 라 못 읽음 — auth 사용자 · 행 · 파일로 봤다')


PHONE = {'E-WD-10': _permitted(_single_shot(p_wd_10)), 'E-WD-11': _permitted(_single_shot(p_wd_11))}

area1.PHONE.update(PHONE)
area1.BUNDLES['area5-time'] = list(PHONE)
tools.CASE_LIMITS.update({case: CASE_LIMIT for case in PHONE})  # 배치 기다림 + 앱 — area3_phone5 의 폰 배치 가설과 같은 상한
