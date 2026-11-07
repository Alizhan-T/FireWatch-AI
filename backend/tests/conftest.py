import sys
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

BACKEND = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(BACKEND))

from app.config import Settings  # noqa: E402
from app.main import create_app  # noqa: E402

FIXTURES = Path(__file__).parent / "fixtures"


def make_settings(tmp: Path, detector: str = "heuristic") -> Settings:
    s = Settings()
    s.database_path = tmp / "test.db"
    s.media_dir = tmp / "media"
    s.demo_assets_dir = tmp / "demo_assets"
    s.detector = detector
    s.firebase_credentials = ""
    return s


@pytest.fixture
def settings(tmp_path):
    return make_settings(tmp_path)


@pytest.fixture
def client(settings):
    with TestClient(create_app(settings)) as c:
        yield c


@pytest.fixture
def fire_jpg() -> bytes:
    return (FIXTURES / "fire_crop.jpg").read_bytes()


@pytest.fixture
def no_fire_jpg() -> bytes:
    return (FIXTURES / "no_fire.jpg").read_bytes()
