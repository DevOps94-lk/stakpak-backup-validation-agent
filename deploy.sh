#!/bin/bash
set -e

echo "──────────────────────────────────────"
echo " Stakpak Deploy Script"
echo "──────────────────────────────────────"

# Ensure .env exists
if [ ! -f .env ]; then
  echo "ERROR: .env file not found. Copy .env.example and fill in values."
  exit 1
fi

echo "▶ Pulling latest code..."
git pull origin main

echo "▶ Building images..."
docker compose --env-file .env build --no-cache

echo "▶ Restarting containers..."
docker compose --env-file .env up -d

echo "▶ Removing unused images..."
docker image prune -f

echo "▶ Container status:"
docker compose ps

echo ""
echo "✔ Deployed successfully!"
echo "  App → http://$(curl -s ifconfig.me)"
