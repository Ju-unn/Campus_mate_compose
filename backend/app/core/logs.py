"""운영(uvicorn)은 루트 로거에 핸들러가 없고 수준이 WARNING 이라 INFO 가 버려진다.

INFO 한 줄이 Cloud Run 로그에 보여야 하는 로거에만 수준과 핸들러를 단다 — app 전체 수준은 건드리지 않는다."""
import logging
import sys


class _StderrHandler(logging.StreamHandler):
    """그때그때의 sys.stderr 로 쓴다(테스트가 stderr 를 바꿔도 닫힌 파일에 쓰지 않는다)."""

    def __init__(self):
        super().__init__()

    @property
    def stream(self):
        return sys.stderr

    @stream.setter
    def stream(self, _value):
        pass


def show_info(logger: logging.Logger) -> None:
    logger.setLevel(logging.INFO)
    handler = _StderrHandler()
    handler.setFormatter(logging.Formatter("%(levelname)s %(name)s: %(message)s"))
    logger.addHandler(handler)
