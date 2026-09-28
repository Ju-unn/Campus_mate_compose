"""사진 한 번에 저장(PUT /me/photos)의 칸 배치를 읽는다. 저장소를 모르는 순수 함수라 따로 둔다."""
import json

MIN_PHOTOS, MAX_PHOTOS = 2, 4  # 온보딩 04-2 와 같다(profile_photos 주석 "최소 2장", check 0~3)


def parse_layout(raw: str, new_count: int, avatar_source: int) -> list[str | int]:
    """칸 순서대로 남길 사진 id(str) 또는 새 파일 번호(int)를 돌려준다. 하나라도 안 맞으면 ValueError.

    올린 파일은 전부 한 번씩 써야 한다 — 안 쓴 파일을 받아 두면 SafeSearch · 업로드 값만 나가고 아무 데도 안 붙는다."""
    try:
        slots = json.loads(raw)
    except json.JSONDecodeError as error:
        raise ValueError("layout 이 JSON 이 아니다") from error
    if not isinstance(slots, list) or not MIN_PHOTOS <= len(slots) <= MAX_PHOTOS:
        raise ValueError("칸은 2~4개다")
    parsed: list[str | int] = []
    for slot in slots:
        if isinstance(slot, dict) and slot.keys() == {"keep"} and isinstance(slot["keep"], str):
            parsed.append(slot["keep"])
        # bool 은 int 의 하위형이라 isinstance 로는 true 가 1 번 파일로 읽힌다 — type 으로 본다.
        elif isinstance(slot, dict) and slot.keys() == {"new"} and type(slot["new"]) is int:
            parsed.append(slot["new"])
        else:
            raise ValueError("칸은 keep(문자열) 또는 new(정수) 하나다")
    kept = [s for s in parsed if isinstance(s, str)]
    new = [s for s in parsed if isinstance(s, int)]
    if len(set(kept)) != len(kept) or sorted(new) != list(range(new_count)):
        raise ValueError("같은 사진을 두 번 쓰거나 올린 파일과 번호가 안 맞는다")
    if not 0 <= avatar_source < len(parsed):
        raise ValueError("아바타 원본 칸 번호가 범위 밖이다")
    return parsed
