# syntax=docker/dockerfile:1

# ---------- build 階段：用 node 編譯出靜態檔 ----------
FROM node:22-slim AS build
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci
COPY . .
RUN npm run build          # 產出 /app/dist

# ---------- serve 階段：只留 nginx + 靜態檔 ----------
FROM nginx:alpine
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/dist /usr/share/nginx/html
EXPOSE 80
