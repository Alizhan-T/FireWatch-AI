FROM python:3.12-slim
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 YOLO_OFFLINE=1 \
    YOLO_CONFIG_DIR=/app/data/.ultralytics OMP_NUM_THREADS=2
WORKDIR /app
RUN apt-get update && apt-get install -y --no-install-recommends ffmpeg libgl1 libglib2.0-0 \
    && rm -rf /var/lib/apt/lists/*
COPY requirements.txt requirements-server.txt ./
# Install CPU wheels first: no CUDA runtime is needed for this CPU inference service.
RUN pip install --no-cache-dir torch torchvision --index-url https://download.pytorch.org/whl/cpu \
    && pip install --no-cache-dir -r requirements.txt -c requirements-server.txt
COPY app ./app
COPY main.py ./main.py
COPY models ./models
COPY demo_assets ./demo_assets
COPY tests/fixtures ./tests/fixtures
RUN useradd --uid 10001 --create-home firewatch \
    && mkdir -p /app/data && chown -R firewatch:firewatch /app/data /app/demo_assets
USER firewatch
EXPOSE 8000
HEALTHCHECK --interval=30s --timeout=5s --start-period=120s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/live', timeout=3)"
# One process owns the SQLite database and camera worker; do not add --workers > 1.
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000", "--workers", "1", "--limit-concurrency", "64", "--timeout-keep-alive", "5"]
