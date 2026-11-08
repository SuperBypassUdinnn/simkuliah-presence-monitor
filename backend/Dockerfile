# syntax=docker/dockerfile:1
#
# Simkuliah backend container.
# Multi-platform Python 3.11-slim image running the FastAPI app behind uvicorn.
FROM python:3.11-slim

WORKDIR /app

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

# Runtime dependencies required by the backend (ddddocr ONNX model, curl for
# health checks, OpenGL libs for image processing).
RUN apt-get update && apt-get install --no-install-recommends -y \
    libgl1 \
    libglib2.0-0 \
    curl \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt

COPY app ./app

EXPOSE 8000

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
