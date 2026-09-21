"""HTTPException 에 실어 보내는 detail 문구를 한 곳에 모은다.

앱이 문구를 그대로 화면에 띄우는 곳이 있어서 문구를 바꾸면 화면이 바뀐다 —
고칠 일이 생기면 여기서만 고친다. 상태코드는 문구를 쓰는 쪽에 그대로 둔다
(같은 문구가 400 과 422 로 나가는 자리가 있어 한 쌍으로 묶으면 오히려 헷갈린다).
"""

# 로그인 · 게이트(student_verification/current_user.py)
LOGIN_REQUIRED = "로그인이 필요해요"
SESSION_EXPIRED = "세션이 만료됐어요, 다시 로그인해 주세요"
STUDENT_VERIFICATION_REQUIRED = "학생증 인증을 먼저 끝내 주세요"
DEPARTMENT_REQUIRED = "학과 정보를 먼저 입력해 주세요"

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

# 프로필 · 사진 · 아바타
PROFILE_NOT_FOUND = "프로필을 찾을 수 없어요"
PROFILE_INCOMPLETE = "프로필을 먼저 완성해 주세요"
NICKNAME_TAKEN = "이미 있는 닉네임이에요"
# 읽을 수 없는 사진(학생증 제출·프로필 사진 업로드가 같은 문구를 쓴다).
PHOTO_UNREADABLE = "사진을 다시 확인해 주세요"
PHOTO_NOT_SAFE = "부적절한 사진은 올릴 수 없어요"
PHOTO_NOT_FOUND = "지울 사진이 없어요"
AVATAR_ALREADY_CREATED = "아바타는 한 번만 만들 수 있어요"
AVATAR_SOURCE_REQUIRED = "아바타 원본 사진을 먼저 골라 주세요"

# 카드 · 수락함
CARD_NOT_FOUND = "카드를 찾을 수 없어요"
CARD_ALREADY_DECIDED = "이미 결정한 카드예요"
CARD_EXPIRED = "지난 카드예요"
ACCEPTANCE_NOT_FOUND = "수락을 찾을 수 없어요"
ACCEPTANCE_ALREADY_ANSWERED = "이미 답한 수락이에요"
ACCEPTANCE_EXPIRED = "기한이 지났어요"
UNKNOWN_NOTIFICATION_SETTING = "알 수 없는 알림 설정이에요"
