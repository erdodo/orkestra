FROM node:22-alpine AS deps
WORKDIR /app
COPY package*.json ./
RUN npm ci

FROM node:22-alpine AS builder
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY . .
RUN node node_modules/.bin/prisma generate
RUN npm run build

FROM node:22-alpine AS runner
WORKDIR /app
ENV NODE_ENV=production

COPY --from=builder /app/.next ./.next
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/package.json ./package.json
COPY --from=builder /app/server.ts ./server.ts
COPY --from=builder /app/lib ./lib
COPY --from=builder /app/prisma ./prisma
COPY --from=builder /app/app/generated ./app/generated
COPY --from=builder /app/prisma.config.ts ./prisma.config.ts
COPY --from=builder /app/tsconfig.json ./tsconfig.json
COPY --from=builder /app/next.config.ts ./next.config.ts

VOLUME ["/app/dev.db"]
EXPOSE 3081

CMD ["node", "node_modules/.bin/tsx", "server.ts"]
