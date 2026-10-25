FROM python:3.13-slim-bookworm

ENV PORT=8080 \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

RUN groupadd --system --gid 10001 app \
    && useradd --system --uid 10001 --gid app \
       --no-create-home --shell /usr/sbin/nologin app

COPY --chown=10001:10001 app/app.py ./app.py

USER 10001:10001

EXPOSE 8080

CMD ["python", "app.py"]
