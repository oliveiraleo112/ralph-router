# Multi-stage Dockerfile for Agrofel Dashboard (FastAPI)
# Builder: installs python deps into /install
FROM python:3.11-slim AS builder

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

# Install build deps only in builder
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    gcc \
  && rm -rf /var/lib/apt/lists/*

# Copy requirements and install into /install prefix
COPY requirements.txt /app/requirements.txt
RUN pip install --upgrade pip && \
    pip install --prefix=/install -r /app/requirements.txt

# Copy application source
COPY . /app

# Final runtime image
FROM python:3.11-slim
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app
# Copy installed packages and app code from builder
COPY --from=builder /install /install
COPY --from=builder /app /app

# Ensure Python can find packages installed to /install
ENV PYTHONPATH=/install/lib/python3.11/site-packages

EXPOSE 8000

# Run with uvicorn
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
