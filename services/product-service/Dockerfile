# ============================================
# Stage 1: Build dependencies
# ============================================
FROM python:3.11-slim AS builder

WORKDIR /app

# Install build dependencies (will not be in final image)
RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements first for layer caching
COPY requirements.txt .

# Install Python packages to a specific directory we can copy later
RUN pip install --no-cache-dir --user -r requirements.txt

# ============================================
# Stage 2: Runtime image
# ============================================
FROM python:3.11-slim AS runtime

# Create non-root user
RUN groupadd -r appuser && useradd -r -g appuser appuser

WORKDIR /app

# Copy installed packages from builder
COPY --from=builder /root/.local /home/appuser/.local

# Copy application code
COPY --chown=appuser:appuser . .

# Make Python packages findable
ENV PATH=/home/appuser/.local/bin:$PATH
ENV PYTHONPATH=/home/appuser/.local/lib/python3.11/site-packages
ENV PYTHONUNBUFFERED=1
ENV PYTHONDONTWRITEBYTECODE=1

USER appuser

EXPOSE 3002

HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:3002/health')" || exit 1

# Use gunicorn (production WSGI server), NOT flask run
# 4 workers handle ~4000 req/sec on a 1 vCPU container
CMD ["gunicorn", "--bind", "0.0.0.0:3002", "--workers", "4", "--timeout", "30", "--access-logfile", "-", "app:app"]
