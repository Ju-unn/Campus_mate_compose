"""영역 4 약관 두 가설(묶음 area4-terms) — E-HEART-50(약관 1부에 무료 하트 문장) · E-SET-57(02-c "보기 ›" 가 약관 페이지를 로그인 없이 연다).
앱이 여는 노션 공개 페이지(frontend/lib/consent/model/consent_links.dart)가 대상이다. 기대값은 바탕화면 E2E_최종테스트_시나리오.md 의 그 줄.

E-HEART-50  폰 없이 PC 만. 노션은 스크립트로 그리는 페이지라 HTML 에는 글이 없어, 공개 페이지가 쓰는 chunk 주소(loadCachedPageChunkV2 — 비공식)로
            블록 글을 받는다. 앱 상수에서 읽은 페이지 id · 1부 앵커로 "문장이 1부 안(1부 머리글 뒤 · 2부 머리글 앞)에 있는지" 본다.
            주소를 못 받거나 모양이 바뀌어 못 읽으면 fail 이 아니라 blocked(문장이 없다는 증거가 아니다).
E-SET-57    폰 A(실폰). 앱이 02-c 에서 이용약관 "보기" 를 누르고 멈추면(step) PC 가 맨 앞이 브라우저인지 · uiautomator 화면 글자에 페이지 제목이 보이는지 ·
            로그인 요구(Log in · Sign up · Continue with)가 없는지 본다. 제목 글자가 안 읽히면(브라우저가 웹 글을 안 내줌 · 아직 로딩 · 크롬 첫 실행 화면) blocked.
            시나리오의 "페이지 제목" 은 노션 페이지 이름 "약관동의" 이고, 이용약관 1부 위치로 스크롤됐는지(앵커)는 보지 않는다.
"""

import html
import json
import re
import time
import unicodedata
import urllib.request
import uuid

from e2e import area1, notify, tools
from e2e.area1 import Check, _app, _signed_in
from e2e.area4_set56 import _front
from e2e.tools import Blocked

LINKS = tools.ROOT / 'frontend' / 'lib' / 'consent' / 'model' / 'consent_links.dart'
SITE = 'https://golden-leech-197.notion.site'  # 같은 페이지의 공개 주소(consent_links.dart 주석) — chunk 주소는 이 도메인이 받는다
SENTENCE = '무료로 받은 하트는 현금으로 바꾸거나 다른 회원에게 줄 수 없고, 유효기간은 없습니다'
TITLE = '약관동의'  # 노션 페이지 이름
PART2 = '2부'
LOGIN_WORDS = (r'\blog in\b', r'\bsign up\b', r'\bcontinue with\b')  # 노션 로그인 벽 글자(단어 경계 — "dialog in" 에 안 걸리게). 한글 "로그인" 은 약관 본문에도 나와 안 쓴다
FIRST_RUN_WORDS = ('welcome to chrome', 'use without an account', 'accept & continue')  # 크롬 첫 실행 화면 — 페이지가 아니다
FRONT_WAIT = 10  # 앱을 누른 뒤 맨 앞이 브라우저로 바뀌기를 기다리는 시간(초)
PAGE_WAIT = 30  # 브라우저에 제목 글자가 나타나기를 기다리는 시간(초) — 노션은 스크립트로 그려 느리다
FETCH_WAIT = 30


def page_ids():
    """consent_links.dart 가 앱에서 여는 주소 → (페이지 id, 1부 앵커 id, 2부 항목 앵커 id). 못 읽으면 Blocked(앱 쪽 모양이 바뀜)."""
    text = LINKS.read_text(encoding='utf-8')
    page = re.search(r"_page = '[^']*?([0-9a-f]{32})'", text)
    terms = re.search(r"termsLink = Uri\.parse\('\$_page#([0-9a-f]{32})'", text)
    privacy = re.search(r"privacyItemsLink = Uri\.parse\('\$_page#([0-9a-f]{32})'", text)
    if not (page and terms and privacy):
        raise Blocked('consent_links.dart 에서 노션 주소(_page · termsLink · privacyItemsLink)를 못 읽음 — 앱 쪽 모양이 바뀜')
    return tuple(str(uuid.UUID(m.group(1))) for m in (page, terms, privacy))


def fetch_page(page_id):
    """공개 노션 페이지의 recordMap 블록들. 못 받으면 Blocked."""
    body = json.dumps({'page': {'id': page_id}, 'limit': 100, 'cursor': {'stack': []}, 'chunkNumber': 0, 'verticalColumns': False}).encode()
    request = urllib.request.Request(f'{SITE}/api/v3/loadCachedPageChunkV2', body, {'Content-Type': 'application/json', 'User-Agent': 'Mozilla/5.0'})
    try:
        with urllib.request.urlopen(request, timeout=FETCH_WAIT) as reply:
            return json.loads(reply.read())['recordMap']['block']
    except (OSError, ValueError, KeyError) as e:
        raise Blocked(f'노션 공개 페이지 글을 못 받음({type(e).__name__} {e}) — 문장이 없다는 증거가 아님') from e


def _value(blocks, block_id):
    node = (blocks.get(block_id) or {}).get('value') or {}
    return node.get('value', node)


def _title(blocks, block_id):
    return ''.join(part[0] for part in _value(blocks, block_id).get('properties', {}).get('title', []))


def _flat(text):
    return re.sub(r'\s+', ' ', unicodedata.normalize('NFC', text)).strip()


def heart_50(run):
    page, terms, privacy = page_ids()
    blocks = fetch_page(page)
    order = _value(blocks, page).get('content')
    if not order or terms not in order or privacy not in order:
        raise Blocked('받은 페이지에서 1부 앵커 · 블록 순서를 못 읽음 — 노션 쪽 모양이 바뀜')
    end = next((i for i, b in enumerate(order) if _flat(_title(blocks, b)).startswith(PART2)), order.index(privacy))
    first = order.index(terms)
    missing = [b for b in order[first:end] if b not in blocks]
    if missing:  # 첫 chunk(100블록)에 안 든 블록 — 문장이 거기 있어도 없다고 하면 헛 fail
        raise Blocked(f'받은 블록이 모자람(1부 {end - first}개 중 {len(missing)}개 없음) — chunk 더 받아야')
    check = Check()
    found = [i for i, b in enumerate(order) if SENTENCE in _flat(_title(blocks, b))]
    check.that(bool(found), f'페이지에 문장이 없음: "{SENTENCE}"')
    if found:
        check.that(first < found[0] < end, f'문장이 1부 안이 아님(블록 {found[0]} · 1부 머리글 {first} · 2부 시작 {end})')
        check.that(len(found) == 1, f'문장이 {len(found)}번 나옴')
    return check.result(f'앱이 여는 페이지 {page[:8]}… 1부 머리글 뒤 {found[0] - first if found else "-"}번째 블록')


def _texts(dump):
    return [html.unescape(m) for m in re.findall(r'(?:text|content-desc)="([^"]+)"', dump)]


def _read_page(serial):
    """브라우저 화면 글자에 제목이 나타날 때까지(최대 [PAGE_WAIT] 초) 읽는다 → 마지막으로 읽은 글자들."""
    seen = []
    for _ in range(PAGE_WAIT // 3):
        seen = _texts(notify._ui_dump(serial))
        if any(TITLE in t for t in seen):
            break
        time.sleep(3)
    return seen


def p_set_57(run, phone):
    check = Check()
    _, token = _signed_in(run, 'new')
    shown = {}

    def opened(said):
        try:
            top = ''
            for _ in range(FRONT_WAIT):
                top = phone.top()
                if top and tools.PACKAGE not in top:
                    break
                time.sleep(1)
            if not top or tools.PACKAGE in top:
                check.problems.append(f'"보기" 를 눌렀는데 맨 앞이 우리 앱 그대로(브라우저가 안 뜸): {top or "못 읽음"}')
                return
            shown['texts'] = _read_page(phone.serial)
        finally:
            _front(phone.serial)

    _app(check, phone(midway=opened, token_hash=token))
    if check.problems or 'texts' not in shown:
        return check.result()
    flat = ' | '.join(shown['texts']).lower()
    if any(w in flat for w in FIRST_RUN_WORDS) and TITLE not in flat:
        raise Blocked('브라우저가 첫 실행 화면 — 약관 페이지가 아님(브라우저를 한 번 열어 설정을 끝낸 뒤 다시)')
    walls = [m.group(0) for w in LOGIN_WORDS if (m := re.search(w, flat))]
    if TITLE not in flat and not walls:
        raise Blocked(f'브라우저 화면 글자에서 페이지 제목 "{TITLE}" 을 못 읽음({PAGE_WAIT}초) — 웹 글을 안 내주거나 아직 로딩 중. 눈으로 확인 필요')
    check.that(TITLE in flat, f'페이지 제목 "{TITLE}" 이 안 보임')
    check.that(not walls, f'로그인 요구 글자가 보임: {walls}')
    return check.result()


PHONE = {'E-SET-57': p_set_57}
CASES = {'E-HEART-50': heart_50}
area1.PHONE.update(PHONE)
area1.CASES.update(CASES)
area1.BUNDLES['area4-terms'] = ['E-HEART-50', 'E-SET-57']
tools.CASE_LIMITS['E-SET-57'] = 600
