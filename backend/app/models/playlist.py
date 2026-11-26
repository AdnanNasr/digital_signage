from pydantic import BaseModel, ConfigDict, Field, field_validator


class PlaylistInput(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)
    name: str = Field(min_length=1, max_length=80)
    items: list[str] = Field(default_factory=list, max_length=500)
    image_duration: int = Field(default=10, ge=1, le=3600)
    loop: bool = True
    revision: int = Field(default=0, ge=0)

    @field_validator("name")
    @classmethod
    def clean_name(cls, value: str) -> str:
        value = value.strip()
        if not value or any(ord(char) < 32 for char in value):
            raise ValueError("Bitte einen Namen eingeben.")
        return value


class SavedPlaylist(PlaylistInput):
    id: str = Field(pattern=r"^[a-f0-9]{32}$")


class PlaylistDocument(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)
    selected_id: str | None = None
    playlists: list[SavedPlaylist] = Field(default_factory=list, max_length=50)


class PlaylistSelection(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)
    id: str | None
