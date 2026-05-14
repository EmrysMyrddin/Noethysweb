FROM python:3.12

RUN apt-get update && \
    apt-get install -y cron supervisor nginx && \
    rm -rf /var/lib/apt/lists/*

RUN python -m pip install gunicorn

WORKDIR /usr/src/app

COPY ./requirements.txt ./requirements-dev.txt .

RUN pip install psycopg2
RUN pip3 install -r ./requirements-dev.txt

RUN cat <<'EOF' > /etc/supervisor/conf.d/supervisord.conf
[supervisord]
nodaemon=true
logfile=/dev/null
logfile_maxbytes=0

[program:nginx]
command=/usr/sbin/nginx -g 'daemon off;'
autostart=true
autorestart=true
stdout_logfile=/dev/fd/1
stdout_logfile_maxbytes=0
stderr_logfile=/dev/fd/2
stderr_logfile_maxbytes=0

[program:cron]
command=/usr/sbin/cron -f
autostart=true
autorestart=true
stdout_logfile=/dev/fd/1
stdout_logfile_maxbytes=0
stderr_logfile=/dev/fd/2
stderr_logfile_maxbytes=0

[program:app]
command=gunicorn noethysweb.wsgi --bind 127.0.0.1:8000 --limit-request-line 8188
directory=/usr/src/app/noethysweb
autostart=true
autorestart=true
stdout_logfile=/dev/fd/1
stdout_logfile_maxbytes=0
stderr_logfile=/dev/fd/2
stderr_logfile_maxbytes=0
EOF

RUN cat <<'EOF' > /etc/nginx/sites-available/default.conf
server {
    listen 80;

    gzip on;
    gzip_types text/plain text/css application/json application/javascript text/xml application/xml application/xml+rss text/javascript;

    location /static/ {
        alias /usr/src/app/noethysweb/static/;
        expires 30d;
        add_header Cache-Control "public";
    }

    location / {
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }
}
EOF

RUN ln -sf /etc/nginx/sites-available/default.conf /etc/nginx/sites-enabled/ && \
    rm -f /etc/nginx/sites-enabled/default

COPY . .

WORKDIR /usr/src/app/noethysweb

# make sur it is executable so that we can easily manage a running instance like this:
# docker exec noethysweb ./manage.py import_defaut
RUN chmod +x ./manage.py

RUN ./manage.py collectstatic

CMD ["/bin/bash", "-c", "./manage.py migrate && /usr/bin/supervisord -c /etc/supervisor/conf.d/supervisord.conf"]
