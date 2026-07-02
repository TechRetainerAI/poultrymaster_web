# Static marketing site on Cloud Run (nginx serving on $PORT=8080).
FROM nginx:1.27-alpine
RUN rm -f /etc/nginx/conf.d/default.conf
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY index.html /usr/share/nginx/html/index.html
COPY README.md  /usr/share/nginx/html/README.md
EXPOSE 8080
