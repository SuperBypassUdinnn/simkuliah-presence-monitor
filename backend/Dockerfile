# syntax=docker/dockerfile:1
#
# Simkuliah backend container — multi-stage build.
#
# Stage 1: builder — installs build dependencies and wheels into a virtualenv.
# Stage 2: runner — slim runtime image copying only the venv and app code.

# ---------------------------------------------------------------------------
# Stage 1: builder
# ---------------------------------------------------------------------------
FROM python:3.11-slim AS builder

WORKDIR /app

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    VIRTUAL_ENV=/opt/venv \
    PATH="/opt/venv/bin:$PATH"

# Build-time dependencies for compiling wheels (e.g. ddddocr ONNX deps).
RUN apt-get update && apt-get install --no-install-recommends -y \
    build-essential \
    curl \
    git \
    libgl1 \
    libglib2.0-0 \
    && rm -rf /var/lib/apt/lists/*

# Create a virtualenv and install Python requirements into it.
RUN python -m venv /opt/venv
COPY requirements.txt ./
RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir -r requirements.txt

# ---------------------------------------------------------------------------
# Stage 2: runner
# ---------------------------------------------------------------------------
FROM python:3.11-slim AS runner

WORKDIR /app

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    VIRTUAL_ENV=/opt/venv \
    PATH="/opt/venv/bin:$PATH"

# Runtime-only libraries (no build tools).
RUN apt-get update && apt-get install --no-install-recommends -y \
    libgl1 \
    libglib2.0-0 \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Copy the virtualenv from the builder stage.
COPY --from=builder /opt/venv /opt/venv

# Copy application source.
COPY app ./app

EXPOSE 8000

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
