"""HTTPException 에 실어 보내는 detail 문구를 한 곳에 모은다.

앱이 문구를 그대로 화면에 띄우는 곳이 있어서 문구를 바꾸면 화면이 바뀐다 —
고칠 일이 생기면 여기서만 고친다. 상태코드는 문구를 쓰는 쪽에 그대로 둔다
(같은 문구가 400 과 422 로 나가는 자리가 있어 한 쌍으로 묶으면 오히려 헷갈린다).
"""

# 로그인 · 게이트(student_verification/current_user.py)
LOGIN_REQUIRED = "로그인이 필요해요"
SESSION_EXPIRED = "세션이 만료됐어요, 다시 로그인해 주세요"
# Supabase 인증이 잠깐 못 받을 때(5xx · 429 · 연결 실패). 401 이 아니다 — 앱이 로그아웃시키지 않게.
AUTH_UNAVAILABLE = "잠시 뒤 다시 시도해 주세요"
# 소셜 로그인 전환: 학교 메일 확인(POST /school-email/verify) 전. 임시 문구 — 최종은 디자인에서 정한다.
SCHOOL_EMAIL_REQUIRED = "학교 메일 인증을 먼저 끝내 주세요"
STUDENT_VERIFICATION_REQUIRED = "학생증 인증을 먼저 끝내 주세요"
DEPARTMENT_REQUIRED = "학과 정보를 먼저 입력해 주세요"

# 가입 동의(consents, 화면 02-c)
CONSENT_REQUIRED = "약관 동의를 먼저 해 주세요"
CONSENT_INCOMPLETE = "필수 항목에 모두 동의해 주세요"

# 학교 메일 확인(school_email, 소셜 로그인 전환). 최종 문구는 디자인에서 정한다 — 지금은 임시 문구.
SCHOOL_EMAIL_UNKNOWN_DOMAIN = "등록되지 않은 학교 메일이에요"
SCHOOL_EMAIL_BLOCKED = "재가입이 제한된 메일이에요"
# {provider} 에는 SCHOOL_EMAIL_PROVIDER_LABELS 의 이름이 들어간다. 앱은 문구가 아니라 응답의 provider 로 가른다.
SCHOOL_EMAIL_TAKEN = "이 메일은 {provider}로 가입돼 있어요"
SCHOOL_EMAIL_PROVIDER_LABELS = {"kakao": "카카오", "google": "구글", "apple": "애플", "email": "학교 메일"}
# POST /school-email/verify: 임시 이메일 계정 토큰이 거절됐거나 확인된 이메일 계정 하나가 아니다.
SCHOOL_EMAIL_NOT_CONFIRMED = "학교 메일 인증이 끝나지 않았어요"
SCHOOL_EMAIL_ALREADY_VERIFIED = "이미 학교 메일 인증이 끝났어요"
# 소셜(카카오 · 구글 · 애플) 계정만 부른다 — 임시 이메일 계정 자신은 못 쓴다.
SCHOOL_EMAIL_SOCIAL_ONLY = "소셜 로그인 계정만 학교 메일을 인증할 수 있어요"

# 가입 직전 훅(auth_hooks). 앱이 GoTrue 오류 문구로 그대로 받는다.
HOOK_UNKNOWN_DOMAIN = "허용되지 않은 학교 이메일이에요"
HOOK_BLOCKED = "재가입이 제한된 이메일이에요"
HOOK_UNKNOWN_PROVIDER = "가입할 수 없는 계정이에요"

# 기계가 보는 응답(훅·배치). 사람에게 보이지 않아 한국어가 아니다.
INVALID_SIGNATURE = "invalid signature"
UNAUTHORIZED = "unauthorized"

# PostgREST 제약 위반 변환(core/http.py)
ALREADY_REGISTERED = "이미 등록된 정보예요"
INVALID_INPUT = "입력한 값을 다시 확인해 주세요"

# 학생증 인증
VERIFICATION_IN_REVIEW = "이미 검토 중이에요, 결과를 기다려 주세요"
VERIFICATION_ALREADY_DONE = "이미 인증이 완료됐어요"
REAL_NAME_REQUIRED = "실명을 입력해 주세요"
REAL_NAME_INVALID = "이름은 한글이나 영문으로만 적어 주세요"

# 프로필 · 사진 · 아바타
PROFILE_NOT_FOUND = "프로필을 찾을 수 없어요"
PROFILE_INCOMPLETE = "프로필을 먼저 완성해 주세요"
NICKNAME_TAKEN = "이미 있는 닉네임이에요"
NICKNAME_CHANGE_TOO_SOON = "닉네임은 30일에 한 번 바꿀 수 있어요"
PHONE_NUMBER_INVALID = "전화번호를 다시 확인해 주세요"
# 읽을 수 없는 사진(학생증 제출·프로필 사진 업로드가 같은 문구를 쓴다).
PHOTO_UNREADABLE = "사진을 다시 확인해 주세요"
PHOTO_NOT_SAFE = "부적절한 사진은 올릴 수 없어요"
PHOTO_NOT_FOUND = "지울 사진이 없어요"
PHOTOS_CHANGED = "사진이 바뀌었어요, 다시 열어 주세요"
AVATAR_ALREADY_CREATED = "아바타는 한 번만 만들 수 있어요"
AVATAR_SOURCE_REQUIRED = "아바타 원본 사진을 먼저 골라 주세요"
AVATAR_NOT_CREATED = "아바타를 먼저 만들어 주세요"
HEARTS_NOT_ENOUGH = "하트가 모자라요"
# 큐 설정이 비었거나(503) 작업 등록이 실패했을 때(502). 둘 다 사용자가 할 일은 같다 — 잠시 뒤 다시.
AVATAR_QUEUE_UNAVAILABLE = "지금은 아바타를 만들 수 없어요, 잠시 뒤 다시 시도해 주세요"
# 추천 코드(화면 20) — pen 값이 오면 문구를 맞춘다
REFERRAL_CODE_NOT_FOUND = "없는 코드예요, 다시 확인해 주세요"
REFERRAL_CODE_NOT_ALLOWED = "이 코드는 쓸 수 없어요"
REFERRAL_ALREADY_REDEEMED = "추천 코드는 한 번만 입력할 수 있어요"

# 카드 · 수락함
CARD_NOT_FOUND = "카드를 찾을 수 없어요"
CARD_ALREADY_DECIDED = "이미 결정한 카드예요"
CARD_EXPIRED = "지난 카드예요"
ACCEPTANCE_NOT_FOUND = "수락을 찾을 수 없어요"
ACCEPTANCE_ALREADY_ANSWERED = "이미 답한 수락이에요"
ACCEPTANCE_EXPIRED = "기한이 지났어요"
UNKNOWN_NOTIFICATION_SETTING = "알 수 없는 알림 설정이에요"
MATCH_CONFLICT = "매칭 정보를 다시 확인해 주세요"

# 채팅 · 신뢰 확인 게이트
CHAT_NOT_FOUND = "대화를 찾을 수 없어요"
CHAT_CLOSED = "종료된 대화예요"
CHAT_LEFT = "이미 나간 대화예요"
CHAT_PARTNER_LEFT = "상대가 대화를 나갔어요"
TRUST_ALREADY_ANSWERED = "이미 수락했어요"
TRUST_DEADLINE_PASSED = "응답 기한이 지났어요"

# 신고 · 차단 · 정지(조각 6)
# 대상 종류(프로필 · 메시지 · 리뷰 · 투표 글)와 상관없는 한 문구(사용자 10-04). 앱이 글자 그대로 비교한다(safety_errors.dart).
ALREADY_REPORTED = "이미 신고를 완료했어요"
REPORT_DAILY_LIMIT = "오늘은 더 신고할 수 없어요"
MESSAGE_NOT_FOUND = "메시지를 찾을 수 없어요"
ACCOUNT_SUSPENDED = "이용이 제한된 계정이에요"
ACCOUNT_WITHDRAWN = "탈퇴한 계정이에요"

# 커뮤니티
POLL_NOT_FOUND = "질문을 찾을 수 없어요"
POLL_ALREADY_VOTED = "이미 투표했어요"
POLL_DAILY_LIMIT = "오늘은 질문을 더 올릴 수 없어요"

# 지인 리뷰
FRIEND_REVIEW_NOT_FOUND = "리뷰를 찾을 수 없어요"
FRIEND_REVIEW_ALREADY_WRITTEN = "이미 리뷰를 남겼어요"

# 무료로 하트 모으기
HEART_TASK_IN_REVIEW = "이미 확인 중이에요, 결과를 기다려 주세요"
HEART_TASK_MONTHLY_LIMIT = "이번 달에는 더 인증할 수 없어요"
