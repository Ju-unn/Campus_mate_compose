"""문의 사유와 숫자 상수를 한 곳에 둔다. 값은 DB enum(inquiry_reason · inquiry_status) · check 와 같다."""
import re
from typing import Literal

# 사유 코드(DB enum inquiry_reason) → 메일 제목 · 관리자 화면 문구. 앱도 같은 이름을 쓴다.
REASON_LABELS = {
    "account": "계정·인증",
    "payment": "결제·하트",
    "matching": "매칭·카드",
    "safety": "신고·안전",
    "bug": "앱 오류",
    "other": "기타",
}
Reason = Literal["account", "payment", "matching", "safety", "bug", "other"]
Status = Literal["new", "in_progress", "answered"]

# 한 사람이 하루(한국 시간 0시부터)에 보낼 수 있는 문의 수.
DAILY_INQUIRY_LIMIT = 5
# DB check(inquiries_body_length · inquiries_reply_email_length · inquiries_admin_memo_length)와 같은 값이다.
BODY_MAX = 1000
EMAIL_MAX = 254
MEMO_MAX = 1000

# 답장 받을 메일 모양. DB check 보다 조금 더 좁다 — 공백 · 줄바꿈(헤더 주입)뿐 아니라 쉼표 · 세미콜론 · 꺾쇠 · 괄호 · 따옴표도
# 막아 Reply-To 에 주소가 둘 이상 들어가거나 "이름 <주소>" 꼴이 되지 않게 한다. fullmatch 로만 쓴다($ 는 끝의 줄바꿈을 통과시킨다).
# 제어문자(NUL 포함)와 비ASCII(한글 등)도 막는다 — re.ASCII 는 부정 칸 [^...] 이 비ASCII 를 통과시키는 걸 막지 못해 범위로 뺀다.
_PART = r"[^\s@,;:<>()\[\]\"\\\x00-\x1f\x7f-\U0010ffff]+"
REPLY_EMAIL = re.compile(rf"{_PART}@{_PART}\.{_PART}")
