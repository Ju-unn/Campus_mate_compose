"""신고 사유와 숫자 상수를 한 곳에 둔다(계획서 B1). 숫자를 바꿔도 다른 코드는 그대로다."""
from datetime import timedelta

# 사유 코드(DB enum report_reason 과 같은 값) → 화면 문구. 앱이 같은 문구를 쓴다.
REASON_LABELS = {
    "abuse": "욕설 · 비방 · 혐오 표현",
    "sexual": "성적 불쾌감을 주는 내용",
    "spam": "광고 · 스팸 · 외부 유도",
    "fake": "사칭 · 허위 프로필",
    "other": "기타(한 줄 입력)",
}

# 서로 다른 신고자가 이만큼 되면 카드 · 매칭 후보에서 자동으로 가린다(결정 3).
AUTO_HIDE_REPORTERS = 3
# 한 사람이 하루(최근 24시간)에 넣을 수 있는 신고 수.
DAILY_REPORT_LIMIT = 10
DAILY_REPORT_WINDOW = timedelta(hours=24)
# "기타" 한 줄 입력 길이. DB 체크 제약(reports_reason_note_length)과 같은 값이다.
REASON_NOTE_MAX = 200
