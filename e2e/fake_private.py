"""가짜 서버가 실명 · 카톡 아이디 암호화 RPC(20261011010000)를 흉내 내는 법 — 가짜 행의 real_name · kakao_id 는 암호문 열을 복호화한 값이라 친다.
평문 열은 M2 로 없어진다 — 그 이름을 GET select · PATCH 본문에 쓰면 PostgREST 처럼 400 이다(하네스가 평문 열을 안 쓰는지 본다)."""

import re

from e2e.tools import Reply

RPC = re.compile(r'/rest/v1/rpc/(decrypt_profile_private|set_real_name|set_kakao_id)')
PLAIN = ('real_name', 'kakao_id')
GONE = Reply(400, {'code': '42703', 'message': 'column profile_private.real_name/kakao_id does not exist'})


def plain_used(select, body):
    """profile_private 요청이 없어진 평문 열을 쓰는가 — [select] 칸 목록(글자) 또는 PATCH [body]."""
    return any(c.strip() in PLAIN for c in (select or '').split(',')) or any(k in PLAIN for k in (body or {}))


def rpc(path, body, row, create):
    """RPC 하나에 답한다(RPC 가 아니면 None). [row](profile_id) 는 그 행 또는 None, [create](profile_id) 는 새 행을 만들어 돌려준다."""
    match = RPC.fullmatch(path)
    if not match:
        return None
    found = row(body['p_profile'])
    if match[1] == 'decrypt_profile_private':
        return Reply(200, [] if found is None else [{k: found.get(k) for k in PLAIN}])
    field = match[1].removeprefix('set_')
    if found is None and field == 'real_name':  # set_real_name 은 upsert, set_kakao_id 는 UPDATE 전용(행이 없으면 0행)
        found = create(body['p_profile'])
    if found is not None:
        found[field] = body[f'p_{field}'] or None  # 빈 문자열은 null 로
    return Reply(204, None)
