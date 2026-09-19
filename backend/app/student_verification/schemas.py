from pydantic import BaseModel


class VerificationStatusResponse(BaseModel):
    status: str
    has_school_info: bool
    reject_reason: str | None = None


class SchoolInfoRequest(BaseModel):
    department: str
    student_number: str
