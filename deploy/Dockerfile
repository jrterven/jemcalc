FROM python:3.14-slim
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 WEB_STATIC_DIR=/srv/web
WORKDIR /srv/server
COPY server/requirements-lock.txt server/requirements.txt server/pyproject.toml ./
RUN pip install --no-cache-dir -r requirements-lock.txt
COPY server/jemcalc ./jemcalc
RUN pip install --no-cache-dir --no-deps . && useradd --system --uid 10001 --no-create-home jemcalc
COPY app/build/web /srv/web
USER 10001:10001
EXPOSE 8080
CMD ["uvicorn", "jemcalc.production:create_app", "--factory", "--host", "0.0.0.0", "--port", "8080", "--no-access-log", "--ws-max-size", "1048576", "--limit-concurrency", "32"]
