FROM node:24-bookworm-slim

WORKDIR /app

# Cai thu vien theo lockfile; layer nay duoc tai su dung khi chi sua src.
COPY package.json package-lock.json ./
RUN npm ci --omit=dev --no-audit --no-fund

COPY --chown=node:node src ./src

USER node

EXPOSE 3000

HEALTHCHECK --interval=5s --timeout=5s --start-period=15s --retries=3 CMD ["node", "src/healthcheck.js"]

CMD ["node", "src/server.js"]
