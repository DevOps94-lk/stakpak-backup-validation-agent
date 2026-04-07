# ─────────────────────────────────────────────
# Stage 1: Install dependencies
# ─────────────────────────────────────────────
FROM node:20-alpine AS deps

WORKDIR /app

COPY package*.json ./

# Install only production deps, clean npm cache
RUN npm ci --omit=dev && npm cache clean --force

# ─────────────────────────────────────────────
# Stage 2: Production image
# ─────────────────────────────────────────────
FROM node:20-alpine AS production

# Install dumb-init for proper PID 1 signal handling
RUN apk add --no-cache dumb-init

WORKDIR /app

# Run as non-root user for security
RUN addgroup -g 1001 -S nodejs && \
    adduser  -S nodeuser -u 1001 -G nodejs

# Copy deps from stage 1
COPY --from=deps --chown=nodeuser:nodejs /app/node_modules ./node_modules

# Copy app source
COPY --chown=nodeuser:nodejs . .

# Remove any local .env (never bake secrets into image)
RUN rm -f .env .env.example

USER nodeuser

EXPOSE 5000

# dumb-init ensures signals (SIGTERM) are forwarded to node correctly
ENTRYPOINT ["dumb-init", "--"]
CMD ["node", "server.js"]
