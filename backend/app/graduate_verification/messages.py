"""졸업생 인증 API 의 오류 문구와 코드. core/errors.py(공유 파일)를 고치지 않으려고 이 모듈에 둔다.

응답 모양은 인앱결제와 같다: {"detail": <문구>, "code": <코드>} — 앱은 문구가 아니라 code 로 가른다."""

# (문구, 코드) 쌍. 상태 코드는 쓰는 쪽에 둔다.
PREVIOUS_EMAIL_INVALID = ("이전 학교 메일 형식을 다시 확인해 주세요", "previous_email_invalid")
CONSENT_REQUIRED = ("개인정보 수집에 동의해 주세요", "consent_required")
GRADUATE_DISABLED = ("지금은 졸업생 인증을 받지 않아요", "graduate_disabled")
METHOD_MISMATCH = ("졸업생 인증 방법을 먼저 골라 주세요", "method_mismatch")
ALREADY_PENDING = ("이미 심사 중이에요, 결과를 기다려 주세요", "already_pending")
ALREADY_VERIFIED = ("이미 인증이 끝났어요", "already_verified")
ATTEMPTS_EXHAUSTED = ("신청 횟수를 모두 썼어요, 문의해 주세요", "attempts_exhausted")

# 신청 횟수 상한(D3). 만료로 닫힌 신청은 세지 않는다.
MAX_ATTEMPTS = 3

# 관리자가 고르는 반려 사유 코드(D10)와 시스템이 닫는 취소 이유. DB check 와 글자까지 같다.
REJECT_REASONS = frozenset({"unreadable", "not_certificate", "unverifiable", "school_unsupported"})
CANCEL_REASONS = frozenset({"switched", "expired", "verified_otherwise", "account_withdrawn"})
