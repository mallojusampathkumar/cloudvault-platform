# ============================================
# Stage 1: Build dependencies
# ============================================
FROM node:20-alpine AS builder

# Set working directory
WORKDIR /app

# Copy only dependency files first (better layer caching)
COPY package*.json ./

# Install production dependencies with strict lockfile check
# --omit=dev: skip devDependencies (nodemon etc.)
# --no-audit: skip security audit during build (we run trivy separately)
# --no-fund: skip funding messages
RUN npm ci --omit=dev --no-audit --no-fund

# ============================================
# Stage 2: Runtime image (slim & secure)
# ============================================
FROM node:20-alpine AS runtime

# Install dumb-init: a tiny init system for proper signal handling
# Without it, Node.js doesn't receive SIGTERM correctly in containers
RUN apk add --no-cache dumb-init

# Create a non-root user (CIS Docker Benchmark requirement)
# Running as root in containers = security risk
RUN addgroup -g 1001 -S nodejs && \
    adduser -S nodejs -u 1001

WORKDIR /app

# Copy node_modules from the builder stage (no build tools come along)
COPY --from=builder --chown=nodejs:nodejs /app/node_modules ./node_modules

# Copy application source code
COPY --chown=nodejs:nodejs . .

# Drop privileges to non-root user
USER nodejs

# Document which port the app listens on
EXPOSE 3001

# Add HEALTHCHECK so Docker/K8s knows if container is healthy
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD wget --quiet --tries=1 --spider http://localhost:3001/health || exit 1

# Use dumb-init as PID 1, then run node
# This ensures SIGTERM propagates properly for graceful shutdown
ENTRYPOINT ["dumb-init", "--"]
CMD ["node", "index.js"]
