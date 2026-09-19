from app.auth_hooks.schemas import BeforeUserCreatedPayload, HookDecision


def test_payload_parses_user_id_and_email():
    payload = BeforeUserCreatedPayload.model_validate(
        {"user_id": "11111111-1111-1111-1111-111111111111", "user": {"email": "hong@SNU.ac.kr"}}
    )

    assert str(payload.user_id) == "11111111-1111-1111-1111-111111111111"
    assert payload.email_domain == "snu.ac.kr"


def test_reject_decision_serializes_with_message():
    decision = HookDecision.reject("허용되지 않은 학교 이메일이에요")

    assert decision.model_dump() == {"decision": "reject", "message": "허용되지 않은 학교 이메일이에요"}


def test_continue_decision_has_no_message():
    decision = HookDecision.allow()

    assert decision.model_dump() == {"decision": "continue", "message": None}
