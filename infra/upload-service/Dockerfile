FROM python:3.13-slim
RUN pip install --no-cache-dir boto3
WORKDIR /srv
COPY server.py .
EXPOSE 9010
CMD ["python", "server.py"]