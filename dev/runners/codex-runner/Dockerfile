FROM python:3.11-slim
WORKDIR /app
COPY ./runners/codex-runner/requirements.txt /app/requirements.txt
RUN pip install --no-cache-dir -r /app/requirements.txt
COPY ./runners/codex-runner /app
ENV PYTHONUNBUFFERED=1
ENV MODEL_NAME=text-embedding-3-small
ENTRYPOINT ["python", "-m", "runner"]

