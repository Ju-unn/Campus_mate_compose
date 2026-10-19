"""관리자 경로 이름이 E2E 가 서버 전체 경로에 거는 검사를 깨지 않는지(설계 10-18 §8 경로 이름 규칙).

e2e/area4_extra.py 의 FORBIDDEN_HEART · PURCHASE_WORDS 와 같은 목록을 여기 복사했다(e2e 는 `단어 in 경로` 부분 문자열 검사).
e2e 쪽 목록이 바뀌면 이 시험도 같이 고친다.
"""
from app.main import app

FORBIDDEN_HEART = ("refund", "cashout", "transfer", "gift", "send_heart", "send-heart", "exchange",
                   "heart_withdraw", "heart-withdraw", "hearts/withdraw")
PURCHASE_WORDS = ("purchase", "buy", "unlock", "heart_store", "heart-store")
# 사거나 여는 경로는 이것 하나뿐이다(e2e/area4_extra.py PAID_PURCHASE).
PAID_PURCHASE = "/cards/paid/{offer_id}/purchase"


def _paths() -> list[str]:
    return [path.lower() for path in app.openapi()["paths"]]


def test_admin_route_names_avoid_e2e_forbidden_words():
    admin = [p for p in _paths() if p.startswith("/admin")]

    assert len(admin) > 20  # 관리자 경로를 실제로 읽었다
    for word in (*FORBIDDEN_HEART, *PURCHASE_WORDS, "withdraw"):
        assert [p for p in admin if word in p] == [], word


def test_the_only_buying_route_is_still_the_paid_card_one():
    assert [p for p in _paths() if any(w in p for w in PURCHASE_WORDS)] == [PAID_PURCHASE]
