"""Pydantic-схемы запросов/ответов API."""
from __future__ import annotations

from typing import Literal

from pydantic import BaseModel, Field

Severity = Literal["low", "medium", "high", "critical"]
Status = Literal["new", "acknowledged", "resolved", "false_alarm"]
Classification = Literal["fire", "smoke", "fire_smoke", "none"]
# Как был получен инцидент — показывается пользователю явно
DetectionMode = Literal["real_model", "demo_heuristic", "simulated", "manual"]
Source = Literal["simulation", "detection", "manual", "camera"]


class IncidentCreate(BaseModel):
    title: str = Field(min_length=1, max_length=200)
    lat: float = Field(ge=-90, le=90)
    lon: float = Field(ge=-180, le=180)
    severity: Severity = "medium"
    location_name: str | None = Field(default=None, max_length=200)
    description: str | None = Field(default=None, max_length=2000)
    camera_id: str | None = None
    classification: Classification | None = None
    confidence: float | None = Field(default=None, ge=0, le=1)
    detection_id: str | None = None


class IncidentStatusUpdate(BaseModel):
    status: Status


class Incident(BaseModel):
    id: str
    title: str
    description: str | None = None
    source: Source
    camera_id: str | None = None
    location_name: str | None = None
    lat: float
    lon: float
    severity: Severity
    status: Status
    classification: Classification | None = None
    confidence: float | None = None
    detection_mode: DetectionMode
    media_type: Literal["image", "video"] | None = None
    media_url: str | None = None
    media_note: str | None = None
    is_demo: bool
    detection_id: str | None = None
    created_at: str
    updated_at: str


class Box(BaseModel):
    label: Literal["fire", "smoke"]
    confidence: float
    x1: float
    y1: float
    x2: float
    y2: float


class DetectionResult(BaseModel):
    id: str
    status: Literal["completed", "failed"]
    mode: Literal["real_model", "demo_heuristic"]
    provider: str
    model_name: str
    classification: Classification
    fire_detected: bool
    smoke_detected: bool
    confidence: float = Field(description="Max box confidence (real model) или эвристический скор (demo)")
    boxes: list[Box] = []
    processing_ms: int
    image_url: str
    annotated_image_url: str | None = None
    disclaimer: str
    incident_id: str | None = None
    source_video_id: str | None = None
    frame_timestamp_sec: float | None = None
    created_at: str


class DeviceIn(BaseModel):
    token: str = Field(min_length=10, max_length=4096)
    name: str | None = Field(default=None, max_length=100)
    platform: str | None = Field(default="ios", max_length=20)


class Camera(BaseModel):
    id: str
    name: str
    url: str
    lat: float
    lon: float


class CameraWithStatus(Camera):
    """Камера + результат последней реальной проверки потока через FFmpeg."""
    status: Literal["unchecked", "online", "offline"] = "unchecked"
    last_checked_at: str | None = None
    last_frame_at: str | None = None
    last_error: str | None = None
    snapshot_url: str | None = None


class CameraCreate(BaseModel):
    id: str | None = Field(default=None, max_length=64)
    name: str = Field(min_length=1, max_length=200)
    url: str = Field(min_length=4, max_length=2000)
    lat: float = Field(default=43.2389, ge=-90, le=90)
    lon: float = Field(default=76.8897, ge=-180, le=180)


class DemoVideo(BaseModel):
    id: str
    title: str
    filename: str
    video_url: str
    duration_sec: float
    description: str
    location_name: str
    lat: float
    lon: float
    is_demo: bool = True
    badge: str = "DEMO VIDEO"


class AnalyzeVideoFrameRequest(BaseModel):
    timestamp_sec: float = Field(default=0.0, ge=0.0, le=36000.0)
    save_incident: bool = False
    lat: float | None = Field(default=None, ge=-90, le=90)
    lon: float | None = Field(default=None, ge=-180, le=180)
    location_name: str | None = Field(default=None, max_length=200)
