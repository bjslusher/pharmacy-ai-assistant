# Build context MUST be the repository root (matches docker-compose.yml):
#   docker build -f frontend/Dockerfile -t pharmacy-frontend .
FROM node:20-alpine AS build
WORKDIR /app

# package files first for layer cache
COPY frontend/package.json ./
RUN npm install

# app source
COPY frontend/ ./

# Sonoran Forge brand pack (repo-root build context)
RUN mkdir -p public/brand
COPY docs/brand/sf-favicon-16.png public/brand/
COPY docs/brand/sf-favicon-32.png public/brand/
COPY docs/brand/sf-badge-circular.png public/brand/
COPY docs/brand/sf-banner-lockup.png public/brand/
COPY docs/brand/sf-app-icon-192.png public/brand/
COPY docs/brand/sf-app-icon-512.png public/brand/
COPY docs/brand/sf-wordmark-stacked.png public/brand/

ARG VITE_API_URL=/api
ENV VITE_API_URL=$VITE_API_URL
RUN npm run build

FROM nginx:alpine
COPY --from=build /app/dist /usr/share/nginx/html
# nginx.conf was copied into /app during build stage (COPY frontend/ ./)
COPY --from=build /app/nginx.conf /etc/nginx/conf.d/default.conf
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
