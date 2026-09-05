FROM python:3.13-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    ffmpeg \
    fonts-dejavu-core \
    && rm -rf /var/lib/apt/lists/*

RUN pip install --no-cache-dir boto3

WORKDIR /srv
COPY server.py .

EXPOSE 9011
CMD ["python", "server.py"]