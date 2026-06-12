# Static SPA for Cloud Run (nginx on port 8080)
FROM node:20-alpine AS build
WORKDIR /app

# Override at build time: --build-arg VITE_LOGIN_API_URL=https://your-login.run.app
ARG VITE_LOGIN_API_URL=https://poultrymaster-api-git-1024831506678.europe-west1.run.app
ENV VITE_LOGIN_API_URL=${VITE_LOGIN_API_URL}

ARG VITE_FARM_API_URL=https://poultrymaster-farm-api-git-1024831506678.europe-west1.run.app
ENV VITE_FARM_API_URL=${VITE_FARM_API_URL}

COPY package.json package-lock.json ./
RUN npm ci
COPY . .
RUN npm run build

FROM nginx:1.27-alpine
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/dist /usr/share/nginx/html
EXPOSE 8080
