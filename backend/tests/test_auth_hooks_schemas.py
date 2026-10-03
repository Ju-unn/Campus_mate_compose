from app.auth_hooks.schemas import BeforeUserCreatedPayload, HookDecision


def test_payload_parses_email_from_real_supabase_body():
    payload = BeforeUserCreatedPayload.model_validate(
        {"metadata": {"uuid": "11111111-1111-1111-1111-111111111111", "name": "before-user-created"}, "user": {"email": "hong@SNU.ac.kr"}}
    )

    assert payload.email_domain == "snu.ac.kr"


def test_reject_decision_serializes_as_gotrue_error():
    decision = HookDecision.reject("허용되지 않은 학교 이메일이에요")

    assert decision.model_dump(exclude_none=True) == {"error": {"http_code": 422, "message": "허용되지 않은 학교 이메일이에요"}}


def test_allow_decision_is_empty_object():
    decision = HookDecision.allow()

    assert decision.model_dump(exclude_none=True) == {}
