"""영역 2 두 기기(폰 A + 에뮬 B) 투표 글 8 — E-POLL-11 · 12 · 19 · 20 · 21 · 22 · 23 · 29(묶음 area2-two-poll).
기대값은 바탕화면 E2E_최종테스트_시나리오.md 영역 2 의 그 줄이다. 앱 쪽은 frontend/integration_test/area2_two_poll.dart 의 같은 번호(`/A` · `/B`).

글쓴이 쪽과 투표하는 쪽이 따로 움직인다. 글 올리기 · 지우기 · 가림(status=blinded) · 정지 · 투표 · 신고는 PC 가 이번 실행이 만든 계정 ·
글에만 하고(area2._guard), 그 순간 다른 기기 화면이 맞게 바뀌는지는 앱이 본다 — 두 기기의 순서는 [twodev.Sync] 이름표로 맞춘다.
화면은 앱이, 서버 · DB 는 PC 가 판정하고, 둘 다 pass 여야 pass 다. 핸들러(스레드)는 API · DB 읽기 · 쓰기와 Sync 만 하고 Run 의 기록 ·
계정 목록은 만지지 않는다(`run.link` 는 cfg · 키만 읽는다).

시험 글은 피드에서 실사용자에게도 보인다(시나리오 ⚠6) — 가설이 끝나면 앱이 막혀도 글쓴이 토큰으로 지운다(area2_phone_b._cleaned).
기존 글은 건드리지 않는다. 글쓴이는 하루 10개 한도에 걸리지 않는다(계정마다 새로 만들고 글은 1~2개).

계정 · 토큰 준비 순서(시험이 기대한다) — 가설마다 A(폰) 계정이 먼저다:
  11 · 19 · 21 · 22 · 23: 글쓴이(A) → 투표하는 사람(B)   12: 두 기기가 같이 쓰는 계정 → 글쓴이   20: 보는 사람(A) → 글쓴이(B)   29: A → B
"""

import random
from contextlib import contextmanager

from e2e import area1, twodev
from e2e.area1 import Check, _api, _detail, _one, _patch, _rows, _signed_in
from e2e.area2 import _ONCE, _guard, _ledger, _poll, _set_status
from e2e.area2_phone_b import PREFIX, _balance, _cleaned
from e2e.tools import Blocked

NOT_FOUND = '질문을 찾을 수 없어요'  # backend errors.POLL_NOT_FOUND
ALREADY_VOTED = '이미 투표했어요'  # errors.POLL_ALREADY_VOTED
WAIT = 150  # 상대 기기가 할 일을 기다리는 상한(초) — 앱 step 의 기다림(3분)보다 짧아야 PC 가 먼저 이유를 말한다
DEADLINE = 360  # 가설 하나 전체(진행 프로그램의 가설 상한 420 보다 짧게 — 두 기기 실행기가 먼저 이유를 적고 끝낸다)
GONE = (0, '호출 안 됨')  # 핸들러가 안 불린 채 앱만 pass 로 끝났을 때 [Check.reply] 가 읽는 값


def _new_poll(run, author, name):
    """시험 글 하나 → (id, 질문). 질문 끝에 무작위 수를 붙여 앱이 피드에서 이 글만 가려 찾는다."""
    text = f'{name} {random.randint(1000, 9999)}'
    return _poll(run, author, text), f'{PREFIX}{text}'


def _until(sync, name, seconds=WAIT):
    """상대 기기가 [name] 까지 오기를 기다린다. 안 오면 이 쪽을 blocked 로 닫는다(상대가 끝나면 Aborted)."""
    if not sync.wait(name, seconds):
        raise Blocked(f"상대 기기가 {seconds}초 안에 '{name}' 까지 오지 않음")


def _verdict(result, memo, check):
    """두 앱의 합친 결과 + PC 가 본 것. 앱이 pass 일 때만 PC 판정을 더한다(앱이 멈췄으면 서버 값은 아직 의미가 없다)."""
    return check.result(memo) if result == 'pass' else (result, memo)


def _guarded(case):
    """준비(계정 · 글 만들기)가 안 되면 예외가 아니라 blocked."""
    def run_case(run, two):
        try:
            return case(run, two)
        except Blocked as e:
            return 'blocked', str(e)
    return run_case


@contextmanager
def _active_after(run, account):
    """정지를 건 가설이 어떻게 끝나든 계정을 다시 active 로 — 글쓴이 토큰으로 글을 지우려면 active 여야 한다."""
    try:
        yield
    finally:
        _set_status(run, account, 'active')


def _vote(run, poll, who, choice):
    return _api(run, 'POST', f'/community/polls/{poll}/votes', who['token'], {'choice': choice}, **_ONCE)


# ── 투표 글 ─────────────────────────────────────────────────────────────────────────────────────────

def poll_11(run, two):
    """B 가 투표한 글에 B 가 API 로 반대표 → 409 "이미 투표했어요", 표 1행 · 첫 선택(a) 그대로. 화면: B 의 글은 도넛이고 버튼이 없다."""
    check, seen = Check(), {}
    author, a_hash = _signed_in(run, 'home')
    voter, b_hash = _signed_in(run, 'home')
    with _cleaned(run, author):
        poll, question = _new_poll(run, author, '두 번 투표')

        def again(said, sync):  # B 가 O 를 눌러 도넛을 본 뒤
            seen['again'] = _vote(run, poll, voter, 'b')
            sync.set('again')

        result, memo = two({('B', 'voted'): again, ('A', 'after-vote'): lambda said, sync: _until(sync, 'again')},
                           a_job={'token_hash': a_hash, 'question': question}, b_job={'token_hash': b_hash, 'question': question},
                           deadline=DEADLINE)
        if result == 'pass':
            check.reply('같은 글 반대표(API)', seen.get('again', GONE), 409, ALREADY_VOTED)
            votes = _rows(run, f'poll_votes?poll_id=eq.{poll}&select=voter_id,choice')
            check.that([(v['voter_id'], v['choice']) for v in votes] == [(voter['id'], 'a')],
                       f'poll_votes {votes}(기대 B 의 첫 선택 a 한 행)')
        return _verdict(result, memo, check)


def poll_12(run, two):
    """같은 계정을 두 기기에 켜 두고 A 가 투표한 뒤 B 가(옛 화면에서) 투표 → B 토스트 "이미 투표했어요" · 그 카드 도넛(앱 판정).
    1회용 토큰은 새로 받으면 앞의 것이 죽는다 — A 가 로그인을 마친 뒤에 B 의 토큰을 받는다(`signed-in` 뒤 `need-login`)."""
    check = Check()
    voter, a_hash = _signed_in(run, 'home')  # 두 기기가 같이 쓰는 계정
    author = run.account('home')
    with _cleaned(run, author):
        poll, question = _new_poll(run, author, '두 기기')

        def a_in(said, sync):  # A 가 로그인해 글을 띄웠다 — B 가 같은 계정으로 들어와 같은 글을 띄울 때까지 투표를 미룬다
            sync.set('a-in')
            _until(sync, 'b-ready')

        def b_login(said, sync):
            _until(sync, 'a-in')
            return {'token_hash': run.link(voter['email'])}

        def b_ready(said, sync):  # B 가 옛 화면(투표 버튼 있음)을 들고 있다 — A 가 투표하고 나서야 풀어 준다
            sync.set('b-ready')
            _until(sync, 'a-voted')

        result, memo = two({('A', 'signed-in'): a_in, ('A', 'voted'): lambda said, sync: sync.set('a-voted'),
                            ('B', 'need-login'): b_login, ('B', 'ready'): b_ready},
                           a_job={'token_hash': a_hash, 'question': question}, b_job={'question': question}, deadline=DEADLINE)
        if result == 'pass':
            votes = _rows(run, f'poll_votes?poll_id=eq.{poll}&select=voter_id,choice')
            check.that([(v['voter_id'], v['choice']) for v in votes] == [(voter['id'], 'a')],
                       f'poll_votes {votes}(기대 A 의 첫 선택 a 한 행)')
        return _verdict(result, memo, check)


def poll_19(run, two):
    """A 가 "…" → 삭제하기 → 확인 → "삭제했어요"(앱). 투표도 같이 지워지고(poll_votes 0행) 이미 받은 B 하트 +10 은 그대로."""
    check, seen = Check(), {}
    author, a_hash = _signed_in(run, 'home')
    voter, b_hash = _signed_in(run, 'home')
    with _cleaned(run, author):
        poll, question = _new_poll(run, author, '지우기')
        before = _balance(run, voter)

        def b_voted(said, sync):  # B 가 투표해 하트를 받은 직후의 잔액을 적고 A 가 지우기를 기다린다
            seen['balance'] = _balance(run, voter)
            sync.set('b-voted')
            _until(sync, 'a-deleted')

        result, memo = two({('B', 'voted'): b_voted, ('A', 'wait-vote'): lambda said, sync: _until(sync, 'b-voted'),
                            ('A', 'deleted'): lambda said, sync: sync.set('a-deleted')},
                           a_job={'token_hash': a_hash, 'question': question}, b_job={'token_hash': b_hash, 'question': question},
                           deadline=DEADLINE)
        if result == 'pass':
            check.that(seen.get('balance') == before + 10, f'B 투표 직후 잔액 {before} → {seen.get("balance")}(기대 +10)')
            check.that(not _rows(run, f'poll_votes?poll_id=eq.{poll}&select=voter_id'), 'poll_votes 가 남음(글이 지워졌는데)')
            check.that(not _rows(run, f'polls?id=eq.{poll}&select=id'), '지웠는데 글이 남음')
            after = _balance(run, voter)
            check.that(after == seen.get('balance'), f'글을 지운 뒤 B 잔액 {seen.get("balance")} → {after}(기대 그대로)')
        return _verdict(result, memo, check)


def poll_20(run, two):
    """남의 글(B 의 글)에는 "…" 이 없고(앱), A 의 토큰으로 DELETE 하면 404 "질문을 찾을 수 없어요"(없는 글과 같은 답) · 글 그대로."""
    check, seen = Check(), {}
    viewer, a_hash = _signed_in(run, 'home')
    author, b_hash = _signed_in(run, 'home')
    with _cleaned(run, author):
        poll, question = _new_poll(run, author, '남의 글')

        def try_delete(said, sync):
            seen['delete'] = _api(run, 'DELETE', f'/community/polls/{poll}', viewer['token'])
            sync.set('tried')

        result, memo = two({('A', 'seen'): try_delete, ('B', 'seen'): lambda said, sync: _until(sync, 'tried')},
                           a_job={'token_hash': a_hash, 'question': question}, b_job={'token_hash': b_hash, 'question': question},
                           deadline=DEADLINE)
        if result == 'pass':
            check.reply('A 토큰 DELETE', seen.get('delete', GONE), 404, NOT_FOUND)
            check.that(len(_rows(run, f'polls?id=eq.{poll}&select=id')) == 1, '남의 글이 지워짐')
        return _verdict(result, memo, check)


def poll_21(run, two):
    """B 가 A 의 글을 띄워 둔 사이 A 가 글을 지우고 B 가 투표 → 토스트 "질문을 찾을 수 없어요" · B 목록에서 그 글 0(앱).
    PC 는 글쓴이 토큰으로 지우고(204), 없는 글의 투표가 하트를 주지 않았는지 원장을 본다."""
    check = Check()
    author, a_hash = _signed_in(run, 'home')
    voter, b_hash = _signed_in(run, 'home')
    with _cleaned(run, author):
        poll, question = _new_poll(run, author, '지운 뒤 투표')

        def delete(said, sync):  # A 가 글을 화면에 띄운 것을 본 뒤 — B 도 같은 글을 띄우고 있다
            _until(sync, 'a-seen')
            reply = _api(run, 'DELETE', f'/community/polls/{poll}', author['token'])
            if reply[0] != 204:
                raise Blocked(f'글쓴이 삭제 {reply[0]} {_detail(reply[1])}(기대 204)')
            sync.set('deleted')

        result, memo = two({('A', 'seen'): lambda said, sync: sync.set('a-seen'),
                            ('A', 'after'): lambda said, sync: _until(sync, 'deleted'), ('B', 'seen'): delete},
                           a_job={'token_hash': a_hash, 'question': question}, b_job={'token_hash': b_hash, 'question': question},
                           deadline=DEADLINE)
        if result == 'pass':
            check.that(not _rows(run, f'polls?id=eq.{poll}&select=id'), '글이 남음')
            check.that(not _rows(run, f'poll_votes?poll_id=eq.{poll}&select=voter_id'), 'poll_votes 가 생김(없는 글에 투표가 들어감)')
            check.that(_ledger(run, voter, 'poll_vote') == [], f'원장 {_ledger(run, voter, "poll_vote")}(기대 없는 글의 투표는 하트 0)')
        return _verdict(result, memo, check)


def poll_22(run, two):
    """운영자가 글을 가리면(status=blinded) B 의 피드에서 사라지고 상세는 "질문을 찾을 수 없어요"(앱, 상세는 피드 목록을 보므로 새로 고침 뒤).
    PC 는 가리고(서비스 키 PATCH) B 의 토큰으로 투표(404) · 상세 GET(404) 을 보낸다."""
    check, seen = Check(), {}
    author, a_hash = _signed_in(run, 'home')
    voter, b_hash = _signed_in(run, 'home')
    with _cleaned(run, author):
        poll, question = _new_poll(run, author, '가려질 글')
        _guard(run, author['id'])  # 가리는 글은 이번 실행이 만든 글쓴이 것뿐이다

        def blind(said, sync):  # B 가 상세 화면을 열어 둔 채, A 가 글을 보고 있을 때
            _until(sync, 'a-seen')
            _patch(run, f'polls?id=eq.{poll}', {'status': 'blinded'})
            seen['vote'] = _vote(run, poll, voter, 'a')
            seen['detail'] = _api(run, 'GET', f'/community/polls/{poll}', voter['token'])
            sync.set('blinded')

        result, memo = two({('A', 'seen'): lambda said, sync: sync.set('a-seen'),
                            ('A', 'after'): lambda said, sync: _until(sync, 'blinded'), ('B', 'detail'): blind},
                           a_job={'token_hash': a_hash, 'question': question}, b_job={'token_hash': b_hash, 'question': question},
                           deadline=DEADLINE)
        if result == 'pass':
            check.reply('API 투표', seen.get('vote', GONE), 404, NOT_FOUND)
            check.reply('상세 API', seen.get('detail', GONE), 404, NOT_FOUND)
            check.that(not _rows(run, f'poll_votes?poll_id=eq.{poll}&select=voter_id'), 'poll_votes 가 생김(가려진 글에 투표가 들어감)')
        return _verdict(result, memo, check)


def poll_23(run, two):
    """글쓴이(A)가 정지되면 B 가 새로 고쳤을 때 그 글이 안 보인다(앱). 되돌리면 다시 보인다(앱) — 글이 지워진 것이 아니라 숨은 것임.
    정지 계정은 글도 못 지우니 끝에 active 로 되돌린 뒤 글쓴이 토큰으로 지운다. 탈퇴는 같은 조건(author.status = 'active')이라 정지로 갈음."""
    author, a_hash = _signed_in(run, 'home')
    voter, b_hash = _signed_in(run, 'home')
    with _cleaned(run, author), _active_after(run, author):
        poll, question = _new_poll(run, author, '정지된 글쓴이')

        done = []

        def suspend(said, sync):
            _until(sync, 'a-seen')
            _set_status(run, author, 'suspended')
            done.append('suspended')

        def restore(said, sync):
            _set_status(run, author, 'active')
            done.append('restored')

        result, memo = two({('A', 'seen'): lambda said, sync: sync.set('a-seen'), ('B', 'suspended'): suspend, ('B', 'restored'): restore},
                           a_job={'token_hash': a_hash, 'question': question}, b_job={'token_hash': b_hash, 'question': question},
                           deadline=DEADLINE)
        check = Check()
        if result == 'pass':  # 앱이 단계를 하나도 안 말하고 pass 로 끝나도 새지 않게 — 정지 · 복원이 실제로 일어났는지
            check.that(done == ['suspended', 'restored'], f'정지 · 복원 단계가 PC 에서 {done} 만 불림(기대 정지 → 복원)')
        return _verdict(result, memo, check)


def poll_29(run, two):
    """남의 글에는 "신고하기"(앱) · 내 글에는 없다(앱). A 의 토큰으로 POST /reports(target_type=poll) — 남의 글 201 {"ok": true} +
    신고 1행 · 차단 0 · 자동 가림 0, 내 글 · 가려진 글 404. (운영자 디스코드 채널에 신고 알림 1건이 간다.)"""
    check, seen = Check(), {}
    mine, a_hash = _signed_in(run, 'home')
    other, b_hash = _signed_in(run, 'home')
    with _cleaned(run, mine, other):
        mine_poll, mine_question = _new_poll(run, mine, '내 글')
        other_poll, other_question = _new_poll(run, other, '남의 글')
        hidden_poll, _ = _new_poll(run, other, '가려진 글')
        _guard(run, other['id'])
        _patch(run, f'polls?id=eq.{hidden_poll}', {'status': 'blinded'})  # 앱에는 안 보이고 신고만 404 로 받아야 한다

        def report(said, sync):  # 두 기기가 머리줄을 다 본 뒤
            _until(sync, 'b-checked')
            for label, target in (('남의 글', other_poll), ('내 글', mine_poll), ('가려진 글', hidden_poll)):
                body = {'target_type': 'poll', 'target_id': target, 'reason': 'spam'}
                seen[label] = _api(run, 'POST', '/reports', mine['token'], body, **_ONCE)
            sync.set('reported')

        def b_checked(said, sync):
            sync.set('b-checked')
            _until(sync, 'reported')

        result, memo = two({('A', 'checked'): report, ('B', 'checked'): b_checked},
                           a_job={'token_hash': a_hash, 'mine': mine_question, 'other': other_question},
                           b_job={'token_hash': b_hash, 'mine': other_question, 'other': mine_question}, deadline=DEADLINE)
        if result == 'pass':
            check.reply('남의 글 신고', seen.get('남의 글', GONE), 201)
            check.that(seen.get('남의 글', GONE)[1] == {'ok': True}, f'남의 글 신고 본문 {seen.get("남의 글", GONE)[1]}(기대 {{"ok": true}})')
            check.reply('내 글 신고', seen.get('내 글', GONE), 404, NOT_FOUND)
            check.reply('가려진 글 신고', seen.get('가려진 글', GONE), 404, NOT_FOUND)
            reports = _rows(run, f"reports?reporter_id=eq.{mine['id']}&select=target_type,target_id,reason")
            check.that([(r['target_type'], r['target_id']) for r in reports] == [('poll', other_poll)], f'reports {reports}(기대 남의 글 poll 한 행)')
            blocks = _rows(run, f"blocks?blocker_id=eq.{mine['id']}&select=blocked_id")
            check.that(not blocks, f'blocks {len(blocks)}행(기대 0 — 투표 글 신고는 차단하지 않는다)')
            hidden_at = _one(run, f"profiles?id=eq.{other['id']}&select=auto_hidden_at").get('auto_hidden_at')
            check.that(hidden_at is None, f'글쓴이 auto_hidden_at {hidden_at}(기대 null — 투표 글 신고는 자동 가림 없음)')
        return _verdict(result, memo, check)


TWO_POLL = {name: _guarded(case) for name, case in {
    'E-POLL-11': poll_11, 'E-POLL-12': poll_12, 'E-POLL-19': poll_19, 'E-POLL-20': poll_20,
    'E-POLL-21': poll_21, 'E-POLL-22': poll_22, 'E-POLL-23': poll_23, 'E-POLL-29': poll_29,
}.items()}

twodev.TWO.update(TWO_POLL)
area1.BUNDLES['area2-two-poll'] = list(TWO_POLL)
