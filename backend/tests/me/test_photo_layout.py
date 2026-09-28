import pytest

from app.me.photo_layout import parse_layout

A, B = "11111111-aaaa-aaaa-aaaa-000000000001", "11111111-aaaa-aaaa-aaaa-000000000002"


def test_keeps_and_new_files_come_back_in_slot_order():
    assert parse_layout(f'[{{"new": 0}}, {{"keep": "{A}"}}, {{"new": 1}}]', new_count=2, avatar_source=1) == [0, A, 1]


@pytest.mark.parametrize(("raw", "new_count", "avatar_source"), [
    ("not json", 0, 0),
    ('{"keep": "x"}', 0, 0),                                   # 목록이 아님
    (f'[{{"keep": "{A}"}}]', 0, 0),                             # 1칸 — 최소 2장
    (f'[{{"keep": "{A}"}}, {{"new": 0}}, {{"new": 1}}, {{"new": 2}}, {{"new": 3}}]', 4, 0),  # 5칸
    (f'[{{"keep": "{A}"}}, {{"keep": "{A}"}}]', 0, 0),          # 같은 사진 두 번
    (f'[{{"keep": "{A}"}}, {{"new": 0}}, {{"new": 0}}]', 1, 0),  # 같은 파일 두 번
    (f'[{{"keep": "{A}"}}, {{"new": 1}}]', 1, 0),               # 없는 파일 번호
    (f'[{{"keep": "{A}"}}, {{"keep": "{B}"}}]', 1, 0),          # 올린 파일을 안 씀
    (f'[{{"keep": "{A}"}}, {{"keep": "{B}"}}]', 0, 2),          # 원본 칸 번호 범위 밖
    (f'[{{"keep": "{A}"}}, {{"keep": "{B}"}}]', 0, -1),         # 원본 칸 번호 음수
    (f'[{{"keep": "{A}"}}, {{"move": "{B}"}}]', 0, 0),          # 모르는 키
    (f'[{{"keep": 3}}, {{"keep": "{B}"}}]', 0, 0),              # keep 은 문자열
    (f'[{{"keep": "{A}"}}, {{"new": false}}]', 1, 0),           # new 는 정수(bool 아님) — false 는 번호 검사도 0 과 같아 보인다
])
def test_rejects_a_layout_that_does_not_add_up(raw, new_count, avatar_source):
    with pytest.raises(ValueError):
        parse_layout(raw, new_count=new_count, avatar_source=avatar_source)
