from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    supabase_url: str
    supabase_service_role_key: str
    auth_hook_signing_secret: str
    discord_webhook_url: str
    google_cloud_project: str

    @property
    def postgrest_url(self) -> str:
        return f"{self.supabase_url}/rest/v1"
