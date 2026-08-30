import json
import os
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlsplit

import boto3
from botocore.config import Config

ENDPOINT = os.getenv('MINIO_ENDPOINT', 'http://minio:9000')
PUBLIC_ENDPOINT = os.getenv('MINIO_PUBLIC_ENDPOINT', 'http://localhost:9000')
BUCKET = os.getenv('MINIO_BUCKET', 'behang')
ACCESS_KEY = os.getenv('MINIO_ACCESS_KEY', 'minioadmin')
SECRET_KEY = os.getenv('MINIO_SECRET_KEY', 'minioadmin123')
PORT = int(os.getenv('PORT', '9010'))
EXPIRES = int(os.getenv('PRESIGN_EXPIRES', '3600'))

_creds = dict(
    aws_access_key_id=ACCESS_KEY,
    aws_secret_access_key=SECRET_KEY,
    region_name='us-east-1',
    config=Config(signature_version='s3v4'),
)

# Admin ops talk to MinIO inside the compose network.
admin = boto3.client('s3', endpoint_url=ENDPOINT, **_creds)
# Presigned URLs must be signed for the hostname the app will actually use
# (localhost:9000 on this machine), so sign with the public endpoint.
signer = boto3.client('s3', endpoint_url=PUBLIC_ENDPOINT, **_creds)


def setup():
    for attempt in range(60):
        try:
            admin.create_bucket(Bucket=BUCKET)
            break
        except Exception as e:
            err = str(e)
            if 'BucketAlreadyOwnedByYou' in err or 'BucketAlreadyExists' in err:
                break
            time.sleep(2)
            continue
    try:
        admin.put_bucket_cors(
            Bucket=BUCKET,
            CORSConfiguration={
                'CORSRules': [
                    {
                        'AllowedOrigins': ['*'],
                        'AllowedMethods': ['GET', 'PUT', 'POST', 'DELETE', 'HEAD'],
                        'AllowedHeaders': ['*'],
                        'ExposeHeaders': ['ETag'],
                        'MaxAgeSeconds': 3600,
                    }
                ]
            },
        )
    except Exception:
        pass


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def _send(self, code, obj):
        body = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        parts = urlsplit(self.path)
        if parts.path == '/health':
            self._send(200, {'ok': True})
            return
        if parts.path == '/presign/download':
            key = parse_qs(parts.query).get('key', [''])[0]
            if not key:
                self._send(400, {'error': 'missing key'})
                return
            url = signer.generate_presigned_url(
                    'get_object', Params={'Bucket': BUCKET, 'Key': key}, ExpiresIn=EXPIRES
                )
            self._send(200, {'url': url})
            return
        self._send(404, {'error': 'not found'})

    def do_POST(self):
        parts = urlsplit(self.path)
        if parts.path == '/presign/upload':
            try:
                length = int(self.headers.get('Content-Length', 0))
                body = json.loads(self.rfile.read(length) or b'{}')
            except Exception:
                body = {}
            key = body.get('key', '')
            content_type = body.get('content_type', 'application/octet-stream')
            if not key:
                self._send(400, {'error': 'missing key'})
                return
            url = signer.generate_presigned_url(
                    'put_object',
                    Params={'Bucket': BUCKET, 'Key': key, 'ContentType': content_type},
                    ExpiresIn=EXPIRES,
                )
            self._send(200, {'url': url, 'content_type': content_type})
            return
        self._send(404, {'error': 'not found'})

    def do_DELETE(self):
        parts = urlsplit(self.path)
        if parts.path == '/presign/delete':
            key = parse_qs(parts.query).get('key', [''])[0]
            if not key:
                self._send(400, {'error': 'missing key'})
                return
            url = signer.generate_presigned_url(
                    'delete_object', Params={'Bucket': BUCKET, 'Key': key}, ExpiresIn=EXPIRES
                )
            self._send(200, {'url': url})
            return
        self._send(404, {'error': 'not found'})


if __name__ == '__main__':
    setup()
    print(f'presign service listening on :{PORT} (bucket={BUCKET})')
    ThreadingHTTPServer(('0.0.0.0', PORT), Handler).serve_forever()