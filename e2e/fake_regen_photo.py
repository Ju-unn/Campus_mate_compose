"""다시 만들기 사진(`area1_b3.regen_photo`)을 쓰는 가설의 시험이 폰 없이 도는 법 — 사진을 앱 캐시로 옮기는 대신 부른 때만 적는다.
사진을 실제로 옮기는 쪽(사진 세트 폴더 · adb)은 test_area5_photo 가 진짜 함수로 본다."""

from unittest import mock


def patch_regen_photo(case, *modules, when=None):
    """[modules] 가 가져다 쓰는 `regen_photo` 를 기록하는 가짜로 바꾼다. 부를 때마다 [when]() 의 값(없으면 None)을 적어 돌려주는 목록에 더한다 —
    "계정을 만들기 전에 불렀나" 를 가짜 서버가 받은 요청 수 0 으로 볼 때 쓴다."""
    calls = []

    def fake(run, phone):
        calls.append(when() if when else None)

    for module in modules:
        patcher = mock.patch.object(module, 'regen_photo', fake)
        patcher.start()
        case.addCleanup(patcher.stop)
    return calls
