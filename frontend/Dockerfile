# ─────────────────────────────────────────────
# Stage 1: Build React app
# ─────────────────────────────────────────────
FROM node:20-alpine AS builder

WORKDIR /app

COPY package*.json ./
RUN npm ci && npm cache clean --force

COPY . .

# Vite build (outputs to /app/dist)
RUN npm run build

# ─────────────────────────────────────────────
# Stage 2: Serve with hardened Nginx
# ─────────────────────────────────────────────
FROM nginx:1.27-alpine AS production

# Remove default nginx config and default html
RUN rm /etc/nginx/conf.d/default.conf && \
    rm -rf /usr/share/nginx/html/*

# Copy built React app
COPY --from=builder /app/dist /usr/share/nginx/html

# Copy hardened nginx config
COPY nginx.conf /etc/nginx/conf.d/default.conf

# Run nginx as non-root (nginx alpine supports this natively)
RUN chown -R nginx:nginx /usr/share/nginx/html && \
    chown -R nginx:nginx /var/cache/nginx && \
    chown -R nginx:nginx /var/log/nginx && \
    touch /var/run/nginx.pid && \
    chown nginx:nginx /var/run/nginx.pid

USER nginx

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
