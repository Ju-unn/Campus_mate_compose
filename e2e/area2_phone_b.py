"""영역 2 폰 A 한 대 — 2차 18(투표 9 · 하트 제출 흐름 8 · 카드 상세 1). 1차 16 은 area2_phone.py.
기대값은 바탕화면 E2E_최종테스트_시나리오.md 영역 2 의 그 줄이다. 앱 쪽은 frontend/integration_test/area2_b.dart 의 같은 번호.

폰 가설은 area1.PHONE 에 더해 `python -m e2e run area2-phone-b` 한 번으로 돈다. 계정은 `run.account('home')`(온보딩 끝 · active),
판정은 앱이 하고 DB 값은 여기서 본다. 쓰기는 이번 실행이 만든 계정 id 에만(area2._guard). 투표 글은 피드에 실사용자에게도 보여
(시나리오 ⚠6) 가설이 끝나면 — 앱이 막혀도 — 글쓴이 토큰으로 지운다. 시각을 옮기지 않는다.
"""

import random
import time
from collections import Counter
from contextlib import contextmanager
from datetime import datetime, timedelta

from e2e import area1, tools
from e2e.area1 import SEOUL, Check, _api, _app, _detail, _one, _patch, _rows, _signed_in
from e2e.area1_b2 import _ours
from e2e.area2 import (_card, _drop_polls, _grant, _guard, _home, _insert, _ledger, _new_id, _poll, _review, _submission_rows,
                       _submit)
from e2e.area2_phone import _count, _school
from e2e.tools import Blocked

PREFIX = '[E2E] '  # area2._poll 이 붙이는 접두어와 같다 — 피드에서 시험 글을 알아보는 표시
DAILY_LIMIT = '오늘은 질문을 더 올릴 수 없어요'  # backend errors.POLL_DAILY_LIMIT
MONTHLY_LIMIT = '이번 달에는 더 인증할 수 없어요'  # backend errors.HEART_TASK_MONTHLY_LIMIT
THUMB = '\U0001F44D'  # 👍 — 앱이 79자 뒤에 붙이는 👍🏻 의 앞 코드 포인트(뒤 🏻 는 80 에서 잘린다)
NOTICE_SECONDS = 60  # E-HEART-09 "60초 알림 0"
REASONS = ('date_missing', 'not_verified', 'reused')  # heart_task_reject_reason — 문구는 앱이 가진 것을 앱이 본다
FEED_PAGE = 20
# 카드 상세 라벨 — 앱 enum(profile_enums.dart · AnimalTypeLabel · ImpressionTypeLabel · ReligionLabel). DB 값 → 화면 글자의 독립 기준이다.
ANIMAL = {'dog': '강아지상', 'cat': '고양이상', 'fox': '여우상', 'bear': '곰상', 'rabbit': '토끼상', 'deer': '사슴상',
          'wolf': '늑대상', 'hamster': '햄스터상'}
IMPRESSION = {'arab': '아랍상', 'tofu': '두부상', 'kind': '선한상', 'chic': '시크상', 'innocent': '청순상'}
RELIGION = {'none': '무교', 'protestant': '기독교', 'catholic': '천주교', 'buddhist': '불교'}
SURVEY = [-1, -0.5, 0, 0.5, 1, -1, -0.5, 0.5, 1]  # 상대 한 명에게 쓰는 성향 9축(허용값 -1 -0.5 0 0.5 1)


@contextmanager
def _cleaned(run, *accounts):
    """가설이 끝나면(앱이 막혀 예외가 나도) 이 계정들의 글을 글쓴이가 지운다."""
    try:
        yield
    finally:
        for account in accounts:
            _drop_polls(run, account)


def _polls(run, account):
    return _rows(run, f"polls?author_id=eq.{account['id']}&select=id,question,option_a_label,option_b_label")


def _passed(said):
    return said.get('result') == 'pass'


# ── 투표 ────────────────────────────────────────────────────────────────────────────────────────────

def _titled(text):
    return f'{PREFIX}{text} {random.randint(1000, 9999)}'


def p_poll_01(run, phone):
    """커뮤니티 → "질문 올리기" → 입력 → "익명으로 올리기". 앱이 올린 글이 DB 에 한 줄, 선택지는 기본값."""
    check = Check()
    account, token = _signed_in(run, 'home')
    question = _titled('첫 질문')
    with _cleaned(run, account):
        said = _app(check, phone(token_hash=token, question=question))
        if _passed(said):
            rows = _polls(run, account)
            check.that(len(rows) == 1, f'polls {len(rows)}행(기대 1)')
            check.that([r['question'] for r in rows] == [question], f'저장된 질문 {[r["question"] for r in rows]}')
            check.that(all((r['option_a_label'], r['option_b_label']) == ('찬성', '반대') for r in rows), f'선택지 {rows}')
    return check.result()


def p_poll_13(run, phone):
    check = Check()
    account, token = _signed_in(run, 'home')
    with _cleaned(run, account):
        poll = _poll(run, account, '작성자 투표')
        said = _app(check, phone(token_hash=token, question=f'{PREFIX}작성자 투표'))
        if _passed(said):
            votes = _rows(run, f'poll_votes?poll_id=eq.{poll}&select=voter_id,choice')
            check.that(len(votes) == 1, f'poll_votes {len(votes)}행(기대 1)')
            check.that(all(v['voter_id'] == account['id'] for v in votes), '다른 사람의 표가 섞임')
            check.that(all(v['choice'] == 'a' for v in votes), f'O(a) 가 아닌 표 {votes}')
    return check.result()


def _fill_today(run, account, count):
    """오늘 글을 [count] 개 API 로 채운다(하루 한도 때문에 계정당 최대 10)."""
    return [_poll(run, account, f'하루 한도 {i + 1}') for i in range(count)]


def _twelfth(check, run, account, label):
    """한도에 닿은 계정의 다음 글은 429 "오늘은 질문을 더 올릴 수 없어요" 다."""
    reply = _api(run, 'POST', '/community/polls', account['token'], {'question': f'{PREFIX}한도 확인'})
    check.reply(label, reply, 429, DAILY_LIMIT)


def p_poll_14(run, phone):
    """오늘 글 9개를 API 로 채운 뒤 앱이 10번째(성공) · 11번째(오늘은 질문을 더 올릴 수 없어요)를 올린다."""
    check = Check()
    account, token = _signed_in(run, 'home')
    with _cleaned(run, account):
        _fill_today(run, account, 9)
        tenth, eleventh = _titled('열 번째'), _titled('열한 번째')
        said = _app(check, phone(token_hash=token, tenth=tenth, eleventh=eleventh))
        if _passed(said):
            questions = [r['question'] for r in _polls(run, account)]
            check.that(len(questions) == 10, f'polls {len(questions)}행(기대 10)')
            check.that(tenth in questions, '10번째 글이 저장되지 않음')
            check.that(eleventh not in questions, '11번째 글이 저장됨')
            _twelfth(check, run, account, '10개 찬 뒤 다음 글(API)')  # 앱이 본 11번째의 429 를 서버 쪽에서도 본다
    return check.result()


def p_poll_15(run, phone):
    """10개를 채우고(11번째가 429 로 막히는 것을 본 뒤) 하나를 지운 다음 앱이 새 글을 올리면 성공해야 한다."""
    check = Check()
    account, token = _signed_in(run, 'home')
    with _cleaned(run, account):
        ids = _fill_today(run, account, 10)
        _twelfth(check, run, account, '10개 찬 상태 확인(API)')
        check.reply('하나 지우기', _api(run, 'DELETE', f'/community/polls/{ids[0]}', account['token']), 204)
        question = _titled('지운 뒤')
        said = _app(check, phone(token_hash=token, question=question))
        if _passed(said):
            questions = [r['question'] for r in _polls(run, account)]
            check.that(question in questions, '지운 뒤 올린 글이 저장되지 않음')
            check.that(len(questions) == 10, f'polls {len(questions)}행(기대 10)')
    return check.result()


def p_poll_18(run, phone):
    """못 올리는 입력 넷 — 화면은 앱이, API 는 여기서 422 로 본다. 어느 쪽이든 polls 에 한 줄도 늘지 않는다."""
    check = Check()
    account, token = _signed_in(run, 'home')
    bad = {
        '질문 81자': {'question': PREFIX + 'a' * 75},
        '선택지 7자': {'question': f'{PREFIX}선택지', 'option_a_label': 'abcdefg'},
        '공백만': {'question': '   '},
        '두 선택지 같음': {'question': f'{PREFIX}같음', 'option_a_label': '같음', 'option_b_label': '같음'},
    }
    with _cleaned(run, account):
        _app(check, phone(token_hash=token))
        for label, body in bad.items():
            check.reply(label, _api(run, 'POST', '/community/polls', account['token'], body), 422)
        rows = _polls(run, account)
        check.that(not rows, f'polls {len(rows)}행(기대 0 — 못 올리는 글이 저장됨)')
    return check.result()


def p_poll_25(run, phone):
    """피드에 시험 글 25개만 두고(다른 글이 있으면 20 → 25 가 아니라 blocked) 앱이 끝까지 내린다. 글은 계정 셋이 10 · 10 · 5 로 올린다."""
    check = Check()
    existing = _count(run, 'polls?select=id')
    if existing:
        raise Blocked(f'피드에 이미 글 {existing}개가 있다 — 시험 글 25개만 있어야 20 → 25 를 볼 수 있다(실사용자 글이면 지우지 않는다)')
    first, token = _signed_in(run, 'home')
    others = [run.account('home'), run.account('home')]
    authors = [first, *others]
    with _cleaned(run, *authors):
        for who, count in zip(authors, (10, 10, 5)):
            for i in range(count):
                _poll(run, who, f'페이지 {authors.index(who) + 1}-{i + 1}')
        total = _count(run, 'polls?select=id')
        if total != 25:
            raise Blocked(f'준비한 글이 {total}개(기대 25)')
        _app(check, phone(token_hash=token))
    return check.result()


def p_poll_26(run, phone):
    check = Check()
    account, token = _signed_in(run, 'home')
    with _cleaned(run, account):
        _poll(run, account, '상세 보기')
        _app(check, phone(token_hash=token, question=f'{PREFIX}상세 보기'))
    return check.result()


def p_poll_27(run, phone):
    """선택지를 직접 적은 글(짜장 / 짬뽕)을 API 로 올려 둔다."""
    check = Check()
    account, token = _signed_in(run, 'home')
    question = _titled('점심')
    with _cleaned(run, account):
        reply = _api(run, 'POST', '/community/polls', account['token'],
                     {'question': question, 'option_a_label': '짜장', 'option_b_label': '짬뽕'})
        if reply[0] != 201:
            raise Blocked(f'글 올리기 {reply[0]} {_detail(reply[1])}')
        _app(check, phone(token_hash=token, question=question, a='짜장', b='짬뽕'))
    return check.result()


def p_poll_31(run, phone):
    """질문 79자 + 👍🏻(코드 포인트 2개) → 앱이 80 에서 자르고 서버도 받는다(201). 저장된 글은 80자이고 끝이 👍 다."""
    check = Check()
    account, token = _signed_in(run, 'home')
    base = PREFIX + 'a' * 73  # 79자
    with _cleaned(run, account):
        said = _app(check, phone(token_hash=token, base=base))
        if _passed(said):
            rows = _polls(run, account)
            check.that(len(rows) == 1, f'polls {len(rows)}행(기대 1 — 올리기 201)')
            question = rows[0]['question'] if rows else ''
            check.that(len(question) == 80, f'저장된 글 {len(question)}자(기대 코드 포인트 80)')  # 파이썬 len 은 코드 포인트
            check.that(question == base + THUMB, f'저장된 글의 끝 {question[-3:]!r}(기대 👍)')
    return check.result()


# ── 하트 제출 흐름 ──────────────────────────────────────────────────────────────────────────────────

def _reviewing(run, account, task='everytime_post'):
    """API 로 제출해 검수 중 줄 하나를 만들고 그 id 를 돌려준다. 안 되면 준비 실패(blocked)."""
    reply = _submit(run, account, task)
    if reply[0] != 201:
        raise Blocked(f'제출 준비 {reply[0]} {_detail(reply[1])}')
    rows = [r for r in _submission_rows(run, account, task) if r['status'] == 'submitted']
    if len(rows) != 1:
        raise Blocked(f'제출 준비 뒤 검수 중 줄 {len(rows)}개(기대 1)')
    return rows[0]['id']


def _decide(run, account, sid, **fields):
    """운영자 검수 흉내 — 상태 · 사유를 한 번에(check 제약). 안 되면 준비 실패(blocked)."""
    status, body = _review(run, account, sid, **fields)
    if status >= 300:
        raise Blocked(f'검수 저장 {status} {_detail(body)}')


def _balance(run, account):
    rows = _rows(run, f"entitlements?profile_id=eq.{account['id']}&select=heart_balance")
    return rows[0]['heart_balance'] if rows else 0


def _notices(phone):
    """우리 앱 알림의 제목 · 본문 줄만(다른 앱 것은 보지도 남기지도 않는다)."""
    serial = getattr(phone, 'serial', None)
    return _ours(tools.adb(serial, 'shell', 'dumpsys', 'notification', '--noredact', check=False)) if serial else []


def p_heart_04(run, phone):
    check = Check()
    account, token = _signed_in(run, 'home')
    said = _app(check, phone(token_hash=token))
    if _passed(said):
        rows = _rows(run, f"heart_task_submissions?profile_id=eq.{account['id']}&select=id,status,task,reward_hearts,storage_path")
        check.that(len(rows) == 1, f'제출 {len(rows)}행(기대 1)')
        row = rows[0] if rows else {}
        got = (row.get('status'), row.get('task'), row.get('reward_hearts'))
        check.that(got == ('submitted', 'everytime_post', 50), f'제출 줄 {got}(기대 submitted · everytime_post · 50)')
        path = f"{account['id']}/{row.get('id')}.jpg"
        check.that(row.get('storage_path') == path, f"storage_path {row.get('storage_path')!r}(기대 {path})")
        files = set(tools.storage_paths(run.cfg, run.key, 'heart-task-proofs', account['id']))
        check.that(path in files, f'버킷에 heart-task-proofs/{path} 없음')
    return check.result()


def p_heart_05(run, phone):
    check = Check()
    account, token = _signed_in(run, 'home')
    said = _app(check, phone(token_hash=token))
    if _passed(said):
        rows = _submission_rows(run, account)
        check.that([r['status'] for r in rows] == ['submitted'], f'제출 줄 {[r["status"] for r in rows]}(기대 submitted 하나)')
    return check.result()


def p_heart_09(run, phone):
    """검수 중 줄을 만들어 두고, 앱이 18a 에서 "검수중" 을 본 뒤 멈춘 사이에 승인한다 — 앱은 18a 를 다시 열어 "완료" 를 본다.
    원장 +50 한 줄(ref = 제출 id) · 잔액 +50 · 승인 뒤 60초 동안 우리 앱 알림이 새로 생기지 않는다."""
    check = Check()
    account, token = _signed_in(run, 'home')
    sid = _reviewing(run, account)
    before, seen = _balance(run, account), {}

    def approve(step):
        seen['notices'] = _notices(phone)
        _decide(run, account, sid, status='approved')
        seen['at'] = time.monotonic()

    said = _app(check, phone(token_hash=token, midway=approve))
    if 'at' not in seen:
        check.that(not _passed(said), '앱이 승인 전에 멈추지 않음')
        return check.result()
    time.sleep(max(0, NOTICE_SECONDS - (time.monotonic() - seen['at'])))
    fresh = Counter(_notices(phone)) - Counter(seen['notices'])
    check.that(not fresh, f'승인 뒤 {NOTICE_SECONDS}초 안에 새 알림: {sorted(fresh)}')
    ledger = [(r['amount'], r['ref_id']) for r in _rows(run, f"heart_transactions?profile_id=eq.{account['id']}&reason=eq.free_task&select=amount,ref_id")]
    check.that(ledger == [(50, sid)], f'원장 {ledger}(기대 [(50, {sid})])')
    check.that(_balance(run, account) == before + 50, f'잔액 {before} → {_balance(run, account)}(기대 +50)')
    return check.result()


def p_heart_12(run, phone):
    check = Check()
    account, token = _signed_in(run, 'home')
    _decide(run, account, _reviewing(run, account), status='rejected', reject_reason='date_missing')
    _app(check, phone(token_hash=token, reason='date_missing'))
    return check.result()


def p_heart_13(run, phone):
    """사유마다 새로 내고 반려한 뒤 앱을 새로 켜서 18b-2 문구를 본다(반려는 끝 상태라 사유를 바꿀 수 없다 — 줄을 새로 만든다)."""
    check = Check()
    account, token = _signed_in(run, 'home')
    for n, reason in enumerate(REASONS):
        _decide(run, account, _reviewing(run, account), status='rejected', reject_reason=reason)
        _app(check, phone(**({'token_hash': token} if n == 0 else {'fresh': False}), reason=reason), reason)
    return check.result()


def p_heart_14(run, phone):
    check = Check()
    account, token = _signed_in(run, 'home')
    _decide(run, account, _reviewing(run, account), status='rejected', reject_reason='date_missing')
    said = _app(check, phone(token_hash=token, reason='date_missing'))
    if _passed(said):
        statuses = sorted(r['status'] for r in _submission_rows(run, account))
        check.that(statuses == ['rejected', 'submitted'], f'제출 줄 {statuses}(기대 반려 하나 + 새 검수 중 하나)')
    return check.result()


def _seed_approved(run, account, task, count, reward):
    """이번 달(한국 시간) 안의 과거 시각으로 검수 중 줄을 하나씩 넣고 곧바로 승인한다 — 검수 중 줄은 항목마다 하나뿐이라
    여러 줄을 한꺼번에 넣을 수 없고, 승인 트리거가 원장 +reward 를 남긴다. 제출 시각은 트리거가 못 바꾸므로 처음부터 넣는다."""
    _guard(run, account['id'])
    now = datetime.now(SEOUL)
    month_start = now.replace(day=1, hour=0, minute=0, second=0, microsecond=0)
    for i in range(count):
        created = max(now - timedelta(hours=count - i), month_start + timedelta(seconds=i + 1))
        sid = _new_id()
        _insert(run, 'heart_task_submissions', [{'id': sid, 'profile_id': account['id'], 'task': task,
                                                'storage_path': f"{account['id']}/{sid}.jpg", 'status': 'submitted',
                                                'reward_hearts': reward, 'created_at': created.isoformat()}], account['id'])
        _decide(run, account, sid, status='approved')


def p_heart_16(run, phone):
    check = Check()
    account, token = _signed_in(run, 'home')
    _seed_approved(run, account, 'kakao_share', 3, 25)
    _app(check, phone(token_hash=token))
    check.reply('4번째 제출(API)', _submit(run, account, 'kakao_share'), 429, MONTHLY_LIMIT)
    ledger = _ledger(run, account, 'free_task')
    check.that(ledger == [25, 25, 25], f'원장 {ledger}(기대 +25 × 3)')
    return check.result()


def p_heart_21(run, phone):
    """이번 주 poll_vote 원장 2건 → 앱("참여" → 누르면 커뮤니티) → 3건 → 앱 다시 켬("완료" · 눌러도 이동 없음)."""
    check = Check()
    account, token = _signed_in(run, 'home')
    for n, (count, expect) in enumerate(((2, 'open'), (3, 'done'))):
        while len(_ledger(run, account, 'poll_vote')) < count:
            status, body = _grant(run, account, 10, 'poll_vote')
            if status >= 300:
                raise Blocked(f'투표 적립 준비 {status} {_detail(body)}')
        _app(check, phone(**({'token_hash': token} if n == 0 else {'fresh': False}), expect=expect), f'{count}건')
    return check.result()


# ── 카드 상세 10b ───────────────────────────────────────────────────────────────────────────────────

def _shown(run, account):
    """DB 값 → 화면에 나와야 하는 글(앱이 이것과 화면을 맞춘다). 못 읽으면 준비 실패."""
    row = _one(run, f"profiles?id=eq.{account['id']}&select=nickname,mbti,height_cm,student_number,religion,is_smoker,"
                    'animal_type,impression_type,interest_tags,my_traits,ideal_traits,bio,ideal_note')
    if not row:
        raise Blocked(f"프로필 {account['id']} 를 못 읽음")
    survey = {int(r['axis']): float(r['value']) for r in _rows(run, f"survey_answers?profile_id=eq.{account['id']}&select=axis,value")}
    return {
        'nickname': row['nickname'],
        'facts': [['키', f"{row['height_cm']}cm" if row.get('height_cm') else '—'], ['MBTI', row.get('mbti') or '—'],
                  ['학번', f"{row['student_number']}학번" if row.get('student_number') else '—'],
                  ['종교', RELIGION[row['religion']]], ['흡연', '흡연' if row.get('is_smoker') else '비흡연']],
        'look': [ANIMAL[row['animal_type']], IMPRESSION[row['impression_type']]],
        'survey': [survey.get(axis, 0.0) for axis in range(1, 10)],
        'tags': {'관심사': row.get('interest_tags') or [], '특징': row.get('my_traits') or [], '이상형 특징': row.get('ideal_traits') or []},
        'bio': row.get('bio'), 'note': row.get('ideal_note'),
    }


def p_card_90(run, phone):
    """상대 둘 — 값이 다 있는 사람 하나, MBTI · 학번 · 자기소개 · 이상형 글이 없는 사람 하나. 카드 한 장씩을 서비스 키로 넣는다."""
    check = Check()
    opens = _school(run).get('card_opens_at')
    if opens is not None:
        raise Blocked(f'시험대학 card_opens_at = {opens} — null 이어야 오늘 탭에 카드가 보인다(운영 값은 안 바꾼다)')
    me, token = _signed_in(run, 'home')
    full = _home(run, 'female', mbti='INTJ', height_cm=172, religion='catholic', is_smoker=True, animal_type='cat',
                 impression_type='chic')
    for axis, value in enumerate(SURVEY, start=1):
        _patch(run, f"survey_answers?profile_id=eq.{full['id']}&axis=eq.{axis}", {'value': value})
    sparse = _home(run, 'female', mbti=None, student_number=None, bio=None, ideal_note=None)
    for person in (full, sparse):
        _card(run, me, person)
    _app(check, phone(token_hash=token, people=[_shown(run, full), _shown(run, sparse)]))
    return check.result()


PHONE_B = {
    'E-POLL-01': p_poll_01, 'E-POLL-13': p_poll_13, 'E-POLL-14': p_poll_14, 'E-POLL-15': p_poll_15, 'E-POLL-18': p_poll_18,
    'E-POLL-25': p_poll_25, 'E-POLL-26': p_poll_26, 'E-POLL-27': p_poll_27, 'E-POLL-31': p_poll_31,
    'E-HEART-04': p_heart_04, 'E-HEART-05': p_heart_05, 'E-HEART-09': p_heart_09, 'E-HEART-12': p_heart_12,
    'E-HEART-13': p_heart_13, 'E-HEART-14': p_heart_14, 'E-HEART-16': p_heart_16, 'E-HEART-21': p_heart_21,
    'E-CARD-90': p_card_90,
}

area1.PHONE.update(PHONE_B)
area1.BUNDLES['area2-phone-b'] = list(PHONE_B)
