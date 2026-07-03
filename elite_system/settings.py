from __future__ import annotations

from dataclasses import dataclass
import os
from pathlib import Path
from typing import Mapping
from urllib.parse import urlparse


DEFAULT_SQLITE_URL = "sqlite:///data/elite.sqlite"


@dataclass(frozen=True)
class AppSettings:
    database_url: str = DEFAULT_SQLITE_URL

    @property
    def database_backend(self) -> str:
        scheme = urlparse(self.database_url).scheme.casefold()
        if scheme in {"postgres", "postgresql"}:
            return "postgresql"
        if scheme in {"sqlite", "sqlite3", ""}:
            return "sqlite"
        raise ValueError(f"unsupported database backend: {scheme}")

    @property
    def is_cloud_database(self) -> bool:
        return self.database_backend == "postgresql"

    @property
    def sqlite_path(self) -> Path:
        parsed = urlparse(self.database_url)
        if self.database_backend != "sqlite":
            raise ValueError("sqlite_path is only available for sqlite databases")
        if parsed.scheme in {"sqlite", "sqlite3"}:
            raw_path = parsed.path
            if os.name == "nt" and raw_path.startswith("/"):
                if len(raw_path) > 3 and raw_path[2] == ":":
                    raw_path = raw_path[1:]
                else:
                    raw_path = raw_path.lstrip("/")
            return Path(raw_path or "data/elite.sqlite")
        return Path(self.database_url)

    @classmethod
    def from_env(cls, env: Mapping[str, str]) -> "AppSettings":
        return cls(database_url=env.get("ELITE_DATABASE_URL", DEFAULT_SQLITE_URL))
