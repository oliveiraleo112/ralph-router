# Multi-stage Dockerfile for frontend

# Stage 1: build
FROM node:20-alpine AS build

WORKDIR /app

# Build args allow CI to inject Vite env vars at build time
ARG VITE_API_URL=""
ARG VITE_CHATWOOT_URL=""
ENV VITE_API_URL=${VITE_API_URL} VITE_CHATWOOT_URL=${VITE_CHATWOOT_URL}

# Install dependencies
COPY package.json package-lock.json* ./
RUN npm ci --silent || npm install --silent

# Copy source and build
COPY . .
RUN npm run build

# Stage 2: serve with nginx
FROM nginx:alpine

# Remove default nginx content
RUN rm -rf /usr/share/nginx/html/*

# Copy built assets
COPY --from=build /app/dist /usr/share/nginx/html

# Copy nginx config
COPY nginx.conf /etc/nginx/conf.d/default.conf

EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
