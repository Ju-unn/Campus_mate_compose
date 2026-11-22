"""관리자 목록의 번호 쪽 나누기(사용자 요청 2026-11-22: 「이전 1 ~ 10 다음」 으로 모두 보이게).

쿼리 page(1부터) · size(기본 20, 최대 100). 응답은 `{"items", "total", "page", "size"}` — total 은 같은 필터로 센 전체 건수다.
범위 밖 쪽은 빈 items 와 total 이다(웹이 마지막 쪽으로 돌아갈 수 있게).
"""
from dataclasses import dataclass

from fastapi import Query

DEFAULT_SIZE = 20
MAX_SIZE = 100
# offset 이 DB integer 를 넘지 않게(100 * 100000 = 천만).
MAX_PAGE = 100_000


@dataclass(frozen=True)
class Page:
    number: int
    size: int

    @property
    def offset(self) -> int:
        return (self.number - 1) * self.size

    def cut(self, rows: list) -> list:
        """메모리에 다 읽은 줄에서 이 쪽만."""
        return rows[self.offset:self.offset + self.size]

    def body(self, items: list, total: int) -> dict:
        return {"items": items, "total": total, "page": self.number, "size": self.size}


def page_query(page: int = Query(1, ge=1, le=MAX_PAGE), size: int = Query(DEFAULT_SIZE, ge=1, le=MAX_SIZE)) -> Page:
    return Page(page, size)
