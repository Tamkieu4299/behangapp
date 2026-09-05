import json
import os
import subprocess
import tempfile
import time
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlsplit

import boto3
from botocore.config import Config

ENDPOINT = os.getenv('MINIO_ENDPOINT', 'http://minio:9000')
BUCKET = os.getenv('MINIO_BUCKET', 'behang')
ACCESS_KEY = os.getenv('MINIO_ACCESS_KEY', 'minioadmin')
SECRET_KEY = os.getenv('MINIO_SECRET_KEY', 'minioadmin123')
PORT = int(os.getenv('PORT', '9011'))

REEL_W = 1080
REEL_H = 1920
FPS = 30

_creds = dict(
    aws_access_key_id=ACCESS_KEY,
    aws_secret_access_key=SECRET_KEY,
    region_name='us-east-1',
    config=Config(signature_version='s3v4'),
)
admin = boto3.client('s3', endpoint_url=ENDPOINT, **_creds)

_FONT_CANDIDATES = [
    '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
    '/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf',
    '/usr/share/fonts/truetype/freefont/FreeSans.ttf',
]


def _find_font():
    for path in _FONT_CANDIDATES:
        if os.path.exists(path):
            return path
    return None


def _escape_text(value):
    value = (value or '')
    for ch in ['\\', "'", ':', '%']:
        value = value.replace(ch, '\\' + ch)
    return value.replace('\n', ' ').replace('\r', ' ')


def _ext(key):
    return os.path.splitext(key)[1] or '.bin'


def _download(key, dest):
    admin.download_file(BUCKET, key, dest)


def _upload(key, path, content_type='video/mp4'):
    admin.upload_file(
        path, BUCKET, key,
        ExtraArgs={'ContentType': content_type},
    )


def _run_ffmpeg(args):
    proc = subprocess.run(['ffmpeg', '-hide_banner', '-loglevel', 'error', *args],
                          capture_output=True, text=True)
    if proc.returncode != 0:
        raise RuntimeError('ffmpeg failed: %s' % proc.stderr[-2000:])
    return proc


def _filter_complex(day_number, milestone_title):
    font = _find_font()
    fontfile = 'fontfile=%s:' % font if font else ''
    day = _escape_text('Day %s' % day_number)
    drawtexts = [
        "drawtext=%stext='%s':fontcolor=white@0.95:"
        'fontsize=60:x=40:y=h-185:box=1:boxcolor=black@0.35:boxborderw=14' % (
            fontfile, day),
    ]
    if milestone_title:
        title = _escape_text(milestone_title)
        drawtexts.append(
            "drawtext=%stext='%s':fontcolor=white@0.9:"
            'fontsize=32:x=40:y=h-118:box=1:boxcolor=black@0.3:boxborderw=10'
            % (fontfile, title),
        )
    return ';'.join([
        '[0:v]scale=%d:%d:force_original_aspect_ratio=increase,'
        'crop=%d:%d,boxblur=luma_radius=20:chroma_radius=20[bg]'
        % (REEL_W, REEL_H, REEL_W, REEL_H),
        '[0:v]scale=%d:%d:force_original_aspect_ratio=decrease[fg]'
        % (REEL_W, REEL_H),
        '[bg][fg]overlay=(W-w)/2:(H-h)/2,%s[out]' % ','.join(drawtexts),
    ])


def _build_segment(spec, work_dir, media_path, out_path):
    fc = _filter_complex(spec.get('day_number', 1), spec.get('milestone_title'))
    duration = float(spec.get('duration', 1.0))
    is_video = spec.get('media_type') == 'video'
    inputs = ['-loop', '1', '-i', media_path] if not is_video else ['-i', media_path]
    args = [
        *inputs,
        '-t', str(duration),
        '-filter_complex', fc,
        '-map', '[out]',
        '-r', str(FPS),
        '-c:v', 'libx264',
        '-preset', 'veryfast',
        '-crf', '22',
        '-pix_fmt', 'yuv420p',
        '-an',
        '-y', out_path,
    ]
    _run_ffmpeg(args)


def _build_watermark_card(out_path):
    font = _find_font()
    fontfile = 'fontfile=%s:' % font if font else ''
    text = _escape_text('Made with Behang')
    args = [
        '-f', 'lavfi',
        '-i', 'color=c=0x101010:s=%dx%d:r=%d:d=1' % (REEL_W, REEL_H, FPS),
        '-vf', "%sdrawtext=%stext='%s':fontcolor=white@0.85:"
               'fontsize=46:x=(w-text_w)/2:y=(h-text_h)/2'
               % ('', fontfile, text),
        '-c:v', 'libx264',
        '-preset', 'veryfast',
        '-crf', '22',
        '-pix_fmt', 'yuv420p',
        '-an',
        '-y', out_path,
    ]
    _run_ffmpeg(args)


def build_body(body):
    journey_id = body.get('journey_id') or body.get('journeyId')
    entries = body.get('entries')
    if not journey_id or not isinstance(entries, list) or not entries:
        return 400, {'error': 'journey_id and entries[] are required'}
    watermark = bool(body.get('watermark', True))
    work = tempfile.mkdtemp(prefix='behang_reel_')
    output_key = body.get('output_key') or (
        'reels/%s/%s.mp4' % (journey_id, uuid.uuid4().hex[:12]))
    try:
        segments = []
        try:
            for i, spec in enumerate(entries):
                media_key = spec.get('media_key')
                if not media_key:
                    continue
                media_path = os.path.join(work, 'in_%d%s' % (i, _ext(media_key)))
                _download(media_key, media_path)
                seg_path = os.path.join(work, 'seg_%d.mp4' % i)
                _build_segment(spec, work, media_path, seg_path)
                segments.append(seg_path)
            if not segments:
                return 400, {'error': 'no resolvable media entries'}
            if watermark:
                card = os.path.join(work, 'watermark.mp4')
                _build_watermark_card(card)
                segments.append(card)
            list_path = os.path.join(work, 'list.txt')
            with open(list_path, 'w') as f:
                for seg in segments:
                    f.write("file '%s'\n" % seg.replace("'", r"'\''"))
            reel_path = os.path.join(work, 'reel.mp4')
            _run_ffmpeg([
                '-f', 'concat', '-safe', '0', '-i', list_path,
                '-c', 'copy', '-movflags', '+faststart', '-y', reel_path,
            ])
            _upload(output_key, reel_path)
            return 200, {'output_key': output_key, 'segments': len(segments)}
        finally:
            import shutil
            shutil.rmtree(work, ignore_errors=True)
    except Exception as e:
        return 500, {'error': str(e)}


def trim_body(body):
    media_key = body.get('media_key')
    duration = float(body.get('duration', 1.0))
    if not media_key:
        return 400, {'error': 'media_key is required'}
    if media_key.endswith('_clip.mp4'):
        return 200, {'output_key': media_key}
    output_key = body.get('output_key') or (
        '%s_clip.mp4' % media_key.rsplit('.', 1)[0])
    work = tempfile.mkdtemp(prefix='behang_trim_')
    try:
        has = True
        try:
            admin.head_object(Bucket=BUCKET, Key=output_key)
        except Exception:
            has = False
        if not has:
            media_path = os.path.join(work, 'in' + _ext(media_key))
            _download(media_key, media_path)
            out_path = os.path.join(work, 'out.mp4')
            _run_ffmpeg([
                '-i', media_path,
                '-t', str(duration),
                '-c:v', 'libx264',
                '-preset', 'veryfast',
                '-crf', '23',
                '-pix_fmt', 'yuv420p',
                '-an', '-movflags', '+faststart',
                '-y', out_path,
            ])
            _upload(output_key, out_path)
        return 200, {'output_key': output_key}
    finally:
        import shutil
        shutil.rmtree(work, ignore_errors=True)


def read_json(handler):
    length = int(handler.headers.get('Content-Length', 0))
    body = handler.rfile.read(length) if length else b'{}'
    try:
        return json.loads(body or b'{}')
    except Exception:
        return {}


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
        self._send(404, {'error': 'not found'})

    def do_POST(self):
        parts = urlsplit(self.path)
        if parts.path == '/reel/build':
            code, obj = build_body(read_json(self))
            self._send(code, obj)
            return
        if parts.path == '/reel/trim':
            code, obj = trim_body(read_json(self))
            self._send(code, obj)
            return
        self._send(404, {'error': 'not found'})


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


if __name__ == '__main__':
    setup()
    print('reel worker listening on :%d (bucket=%s, font=%s)'
          % (PORT, BUCKET, _find_font()))
    ThreadingHTTPServer(('0.0.0.0', PORT), Handler).serve_forever()