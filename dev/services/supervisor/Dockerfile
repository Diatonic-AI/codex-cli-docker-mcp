FROM python:3.11-slim
WORKDIR /app
COPY ./services/supervisor/requirements.txt /app/requirements.txt
RUN pip install --no-cache-dir -r /app/requirements.txt
COPY ./services/supervisor /app
RUN apt-get update && apt-get install -y docker.io && rm -rf /var/lib/apt/lists/*
CMD ["python", "-u", "main.py"]

