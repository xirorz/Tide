#!/usr/bin/env python3
"""Tide's AI bridge: the one process that talks to an assistant backend for the shell.

Tide's QML (services/EveData.qml) starts it and speaks newline-delimited JSON with it:
  stdin  ← {"op": "...", ...}   one request per line
  stdout → {"ev": "...", ...}   answers, reply events and status, one per line

Backends are configured in ~/.config/Tide/ai.json and reached over one of two protocols:
  "ai-api"  the Tide AI API (~/.config/Tide/docs/AI-API.md), for assistants with chats, approvals and more
  "openai"  any OpenAI-compatible server (LM Studio, Ollama, llama.cpp)  [coming in a later step]
Nothing here knows about any particular assistant. Standard library only."""

import array
import json
import os
import queue
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

CONFIG = Path(os.environ.get('TIDE_AI_CONFIG', Path.home() / '.config/Tide/ai.json'))
HEALTH_EVERY = 30
OUT = threading.Lock()


def emit(**event):
    line = json.dumps(event, ensure_ascii=False)
    with OUT:
        sys.stdout.write(line + '\n')
        sys.stdout.flush()


class Failed(Exception):
    pass


def load_config():
    try:
        config = json.loads(CONFIG.read_text())
    except FileNotFoundError:
        return {}, None
    except (OSError, ValueError) as exc:
        return {}, f'{CONFIG} could not be read: {exc}'
    return config if isinstance(config, dict) else {}, None


def pick(config, role):
    backends = [b for b in config.get('backends') or [] if isinstance(b, dict) and b.get('enabled', True) and b.get('url')]
    wanted = config.get(role)
    return next((b for b in backends if b.get('id') == wanted), None) or (backends[0] if backends else None)


class AiApi:
    """A backend serving the Tide AI API at one base URL."""

    def __init__(self, backend):
        self.base = backend['url'].rstrip('/')
        self.token = None
        if backend.get('tokenFile'):
            self.token = Path(os.path.expanduser(backend['tokenFile'])).read_text().strip()

    def headers(self, body):
        headers = {'Content-Type': 'application/json'} if body is not None else {}
        if self.token:
            headers['Authorization'] = 'Bearer ' + self.token
        return headers

    def call(self, path, method='GET', body=None, timeout=15):
        data = json.dumps(body).encode() if body is not None else None
        request = urllib.request.Request(self.base + path, data, self.headers(body), method=method)
        try:
            with urllib.request.urlopen(request, timeout=timeout) as response:
                raw = response.read()
        except urllib.error.HTTPError as exc:
            try:
                message = json.load(exc).get('error')
            except (ValueError, AttributeError, OSError):
                message = None
            raise Failed(message or f'HTTP {exc.code}') from None
        except OSError as exc:
            raise Failed(f'Not reachable ({getattr(exc, "reason", exc)})') from None
        return json.loads(raw) if raw else {}

    def stream(self, path, body):
        request = urllib.request.Request(self.base + path, json.dumps(body).encode(), self.headers(body), method='POST')
        try:
            response = urllib.request.urlopen(request, timeout=3600)
        except urllib.error.HTTPError as exc:
            try:
                message = json.load(exc).get('error')
            except (ValueError, AttributeError, OSError):
                message = None
            raise Failed(message or f'HTTP {exc.code}') from None
        except OSError as exc:
            raise Failed(f'Not reachable ({getattr(exc, "reason", exc)})') from None
        with response:
            for line in response:
                if line.startswith(b'data: '):
                    if line.strip() == b'data: [DONE]':
                        return
                    try:
                        yield json.loads(line[6:])
                    except ValueError:
                        continue

    def manifest(self):
        return self.call('')

    def health(self):
        return self.call('/health', timeout=5)

    def chats(self):
        return self.call('/chats').get('chats', [])

    def messages(self, chat):
        return self.call(f'/chats/{urllib.parse.quote(chat, safe="")}/messages').get('messages', [])

    def reply(self, chat, text, think, attachments):
        body = dict(text=text, think=bool(think), attachments=attachments or [])
        return self.stream(f'/chats/{urllib.parse.quote(chat, safe="")}/reply', body)

    def cancel(self, chat):
        return self.call(f'/chats/{urllib.parse.quote(chat, safe="")}/cancel', 'POST', {})

    def update_chat(self, chat, change):
        return self.call(f'/chats/{urllib.parse.quote(chat, safe="")}', 'PATCH', change)

    def delete_chat(self, chat):
        return self.call(f'/chats/{urllib.parse.quote(chat, safe="")}', 'DELETE', timeout=30)

    def approvals(self, chat=None):
        return self.call('/approvals' + (f'?chat={urllib.parse.quote(chat)}' if chat else '')).get('approvals', [])

    def decide(self, approval, decision, scope, reason=None):
        return self.call(f'/approvals/{urllib.parse.quote(approval, safe="")}', 'POST',
                         dict(decision=decision, scope=scope, **({'reason': reason} if reason else {})))

    def mode(self, value=None):
        return self.call('/mode', 'PUT', dict(mode=value)) if value else self.call('/mode')

    def power(self, on=None):
        return self.call('/power', 'PUT', dict(on=on), timeout=120) if on is not None else self.call('/power')


    def audio(self, path, data):
        request = urllib.request.Request(self.base + path, data, dict(self.headers(None), **{'Content-Type': 'application/octet-stream'}),
                                         method='POST')
        try:
            with urllib.request.urlopen(request, timeout=60) as response:
                return json.loads(response.read() or b'{}')
        except urllib.error.HTTPError as exc:
            try:
                message = json.load(exc).get('error')
            except (ValueError, AttributeError, OSError):
                message = None
            raise Failed(message or f'HTTP {exc.code}') from None
        except OSError as exc:
            raise Failed(f'Not reachable ({getattr(exc, "reason", exc)})') from None

    def app(self, app, view=None):
        query = f'?view={urllib.parse.quote(view)}' if view else ''
        return self.call(f'/apps/{urllib.parse.quote(app, safe="")}{query}', timeout=30)

    def speech(self, text):
        """The backend's voice for text: (raw 16-bit PCM response, sample rate, channels)."""
        request = urllib.request.Request(self.base + '/voice/speech', json.dumps(dict(text=text)).encode(), self.headers({}), method='POST')
        try:
            response = urllib.request.urlopen(request, timeout=120)
        except urllib.error.HTTPError as exc:
            try:
                message = json.load(exc).get('error')
            except (ValueError, AttributeError, OSError):
                message = None
            raise Failed(message or f'HTTP {exc.code}') from None
        except OSError as exc:
            raise Failed(f'Not reachable ({getattr(exc, "reason", exc)})') from None
        return response, int(response.headers.get('X-Audio-Sample-Rate') or 24000), int(response.headers.get('X-Audio-Channels') or 1)

    def call_open(self):
        return self.call('/voice/call', 'POST', {})

    def call_audio(self, key, pcm, activity=None):
        headers = dict(self.headers(None), **{'Content-Type': 'application/octet-stream'})
        if activity is not None:
            headers['X-Voice-Activity'] = f'{activity:.2f}'
        request = urllib.request.Request(f'{self.base}/voice/call/{key}/audio', pcm, headers, method='POST')
        try:
            with urllib.request.urlopen(request, timeout=30) as response:
                return json.loads(response.read() or b'{}')
        except urllib.error.HTTPError as exc:
            raise Failed(f'HTTP {exc.code}') from None
        except OSError as exc:
            raise Failed(f'Not reachable ({getattr(exc, "reason", exc)})') from None

    def call_stream(self, key, what):
        request = urllib.request.Request(f'{self.base}/voice/call/{key}/{what}', headers=self.headers(None))
        try:
            return urllib.request.urlopen(request, timeout=3600)
        except urllib.error.HTTPError as exc:
            raise Failed(f'HTTP {exc.code}') from None
        except OSError as exc:
            raise Failed(f'Not reachable ({getattr(exc, "reason", exc)})') from None

    def live_stream(self):
        request = urllib.request.Request(f'{self.base}/live', headers=self.headers(None))
        try:
            return urllib.request.urlopen(request, timeout=3600)
        except urllib.error.HTTPError as exc:
            raise Failed(f'HTTP {exc.code}') from None
        except OSError as exc:
            raise Failed(f'Not reachable ({getattr(exc, "reason", exc)})') from None

    def call_close(self, key):
        return self.call(f'/voice/call/{key}/close', 'POST', {})

    def stop_speech(self):
        return self.call('/voice/speech/stop', 'POST', {})

    def check(self, app, item, done):
        return self.call(f'/apps/{urllib.parse.quote(app, safe="")}/check', 'POST', dict(item=item, done=done))

    def dictation_open(self):
        return self.audio('/voice/dictation', b'')['id']

    def dictation_feed(self, key, pcm):
        return self.audio(f'/voice/dictation/{key}/audio', pcm)

    def dictation_finish(self, key, pcm=b''):
        return self.audio(f'/voice/dictation/{key}/finish', pcm)

    def dictation_cancel(self, key):
        return self.audio(f'/voice/dictation/{key}/cancel', b'')


PROTOCOLS = {'ai-api': AiApi}
# The microphone as 16 kHz mono 16-bit PCM on stdout (PipeWire's PulseAudio server).
RECORDER = ['parecord', '--raw', '--format=s16le', '--rate=16000', '--channels=1', '--latency-msec=100']
CHUNK = 16000 * 2 // 4  # A quarter second of audio per request.
TAIL = 0.6


class Speaker:
    """Text read aloud: the backend's voice streams in and plays through PipeWire as it arrives."""

    def __init__(self, client, text):
        self.client = client
        self.text = text
        self.stopped = threading.Event()
        self.player = None
        self.response = None
        threading.Thread(target=self.run, daemon=True).start()

    def stop(self):
        self.stopped.set()
        if self.player:
            self.player.kill()
        if self.response:
            try:
                self.response.close()
            except OSError:
                pass
        try:
            self.client.stop_speech()
        except Failed:
            pass

    def run(self):
        emit(ev='speech', speaking=True)
        try:
            self.response, rate, channels = self.client.speech(self.text)
            self.player = subprocess.Popen(['pacat', '--playback', '--raw', '--format=s16le', f'--rate={rate}', f'--channels={channels}',
                                            '--client-name=Tide', '--stream-name=Assistant voice'], stdin=subprocess.PIPE, stderr=subprocess.DEVNULL)
            with self.response:
                # Her voice is made about as fast as it plays: a second of it is banked first so it never runs dry.
                bank, banked = bytearray(), False
                while not self.stopped.is_set() and (chunk := self.response.read(4800)):
                    if banked:
                        self.player.stdin.write(chunk)
                        continue
                    bank += chunk
                    if len(bank) >= BANK * rate * 2 * channels:
                        self.player.stdin.write(bytes(bank))
                        banked = True
                if not banked and bank and not self.stopped.is_set():
                    self.player.stdin.write(bytes(bank))
            self.player.stdin.close()
            self.player.wait()
            if not self.stopped.is_set():
                emit(ev='speech', speaking=False)
        except (Failed, OSError, ValueError) as exc:
            if not self.stopped.is_set():
                emit(ev='speech', speaking=False, error=str(exc))


CALL_CHUNK = 16000 * 2 // 10  # The microphone goes to a call every 100 ms.
BANK = 1.0  # Seconds of the assistant's voice collected before it plays (after a gap), as the voice window does.


class EchoCancel:
    """PipeWire's echo cancel, only while a call runs: the mic is read through it and the assistant's voice played through
    it, so its voice coming back from speakers is taken out of what the mic hears (otherwise it hears itself and stops,
    or answers its own words). It sits on whatever input and output are the defaults when the call starts, and is gone
    again when the call ends; nothing about the system's audio setup changes."""
    SOURCE, SINK = 'tide_aec_source', 'tide_aec_sink'

    def __init__(self):
        self.module = None

    @staticmethod
    def clear_leftovers():
        """A bridge that died during a call left its echo cancel loaded: it goes."""
        try:
            listed = subprocess.run(['pactl', 'list', 'short', 'modules'], capture_output=True, text=True, timeout=5).stdout
        except (OSError, subprocess.SubprocessError):
            return
        for line in listed.splitlines():
            if 'module-echo-cancel' in line and EchoCancel.SOURCE in line:
                subprocess.run(['pactl', 'unload-module', line.split()[0]], capture_output=True, timeout=5)

    def start(self):
        self.clear_leftovers()
        try:
            def default(kind):
                return subprocess.run(['pactl', f'get-default-{kind}'], capture_output=True, text=True, timeout=5).stdout.strip()
            source, sink = default('source'), default('sink')
            loaded = subprocess.run(['pactl', 'load-module', 'module-echo-cancel', 'aec_method=webrtc',
                                     f'source_name={self.SOURCE}', f'sink_name={self.SINK}',
                                     *([f'source_master={source}'] if source else []), *([f'sink_master={sink}'] if sink else []),
                                     'source_properties=device.description=Tide-call-microphone',
                                     'sink_properties=device.description=Tide-call-voice'],
                                    capture_output=True, text=True, timeout=10)
        except (OSError, subprocess.SubprocessError):
            return False
        if loaded.returncode or not loaded.stdout.strip().isdigit():
            return False
        self.module = loaded.stdout.strip()
        return True

    def stop(self):
        if self.module:
            subprocess.run(['pactl', 'unload-module', self.module], capture_output=True, timeout=5)
            self.module = None


class Loudness:
    """A small voice-activity hint from loudness alone (no extra packages): how far a chunk stands above the room's own
    noise, 0-1. The call uses it as the voice window uses Silero's: quiet chunks reach whisper as silence, so room noise
    doesn't keep whisper busy, and the call knows someone is talking before whisper has the words."""

    def __init__(self):
        self.floor = 50.0

    def __call__(self, pcm):
        samples = array.array('h', pcm[:len(pcm) // 2 * 2])
        if not samples:
            return 0.0
        rms = (sum(x * x for x in samples) / len(samples)) ** 0.5
        # The noise floor follows the quietest chunks quickly and creeps up slowly, so speech never becomes "the room".
        self.floor = min(rms, self.floor) * 0.3 + self.floor * 0.7 if rms < self.floor else self.floor * 1.01
        self.floor = max(self.floor, 5.0)
        # Relative to the room only: microphones differ a lot (one headset's speech measured 150-600, its room 12).
        low, high = 2.5 * self.floor, 6.0 * self.floor
        return 0.0 if rms <= low else 1.0 if rms >= high else (rms - low) / (high - low)


class Call:
    """A hands-free call (`voice.call`): the microphone streams the whole time, the assistant's voice plays as it comes,
    and its events go to the shell, which draws them in the island. On a "stop" event (it stopped because it was talked
    over) whatever of its voice is still buffered here is dropped at once."""

    def __init__(self, client, source=None):
        self.client = client
        self.source = source
        self.closed = threading.Event()
        self.muted = False
        self.key = None
        self.rate = 24000
        self.recorder = None
        self.player = None
        self.player_lock = threading.Lock()
        self.sink = None
        self.echo = None
        self.generation = 0  # bumped when she is stopped: audio queued before that is dropped
        threading.Thread(target=self.run, daemon=True).start()

    def run(self):
        try:
            opened = self.client.call_open()
        except Failed as exc:
            return emit(ev='call', type='error', error=str(exc), ended=True)
        self.key, self.rate = opened['id'], int(opened.get('speechRate') or 24000)
        self.echo = EchoCancel()
        if self.echo.start():
            self.source, self.sink = EchoCancel.SOURCE, EchoCancel.SINK
        else:
            self.sink = None
            emit(ev='call', type='notice', text="Echo cancel isn't available: use a headset so the assistant doesn't hear itself.")
        emit(ev='call', type='open')
        for target in (self.microphone, self.voice, self.events, self.follow_live):
            threading.Thread(target=target, daemon=True).start()

    def microphone(self):
        command = RECORDER + ([f'--device={self.source}'] if self.source else [])
        try:
            self.recorder = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        except OSError as exc:
            emit(ev='call', type='error', error=f'The microphone could not be opened ({exc})')
            return self.close()
        loudness = Loudness()
        while not self.closed.is_set():
            pcm = self.recorder.stdout.read(CALL_CHUNK)
            if not pcm:
                break
            try:
                # Muted: silence keeps the call's timing, and none of the room reaches it.
                if self.muted:
                    self.client.call_audio(self.key, bytes(len(pcm)), 0.0)
                else:
                    self.client.call_audio(self.key, pcm, loudness(pcm))
            except Failed as exc:
                if not self.closed.is_set():
                    emit(ev='call', type='error', error=str(exc))
                    self.close()
                return

    def new_player(self):
        return subprocess.Popen(['pacat', '--playback', '--raw', '--format=s16le', f'--rate={self.rate}', '--channels=1', '--latency-msec=150',
                                 '--client-name=Tide', '--stream-name=Assistant call', *([f'--device={self.sink}'] if self.sink else [])],
                                stdin=subprocess.PIPE, stderr=subprocess.DEVNULL)

    def voice(self):
        """Her voice comes in about as fast as it plays (Breeze makes it at ~1.1x real time), so like the voice window it
        is banked: after any gap, BANK seconds collect before playing starts, and it then plays without running dry."""
        try:
            stream = self.client.call_stream(self.key, 'speech')
        except Failed as exc:
            emit(ev='call', type='error', error=str(exc))
            return self.close()
        with self.player_lock:
            self.player = self.new_player()
        self.chunks = queue.Queue()
        threading.Thread(target=self.play, daemon=True).start()
        with stream:
            while not self.closed.is_set():
                chunk = stream.read1(4800) if hasattr(stream, 'read1') else stream.read(4800)
                if not chunk:
                    break
                self.chunks.put((self.generation, chunk))

    def play(self):
        per_second = self.rate * 2
        bank, since, until = bytearray(), None, 0.0
        while not self.closed.is_set():
            try:
                generation, chunk = self.chunks.get(timeout=0.05)
            except queue.Empty:
                generation, chunk = self.generation, b''
            if generation != self.generation:
                continue  # she was stopped: what was said before the stop is not played
            now = time.monotonic()
            if until and now < until:
                self.write(chunk)
                until += len(chunk) / per_second
                continue
            # The player ran dry (or has not started): bank before playing again; a short phrase plays when it ends.
            if chunk:
                bank += chunk
                since = since or now
            if bank and (len(bank) >= BANK * per_second or now - since >= BANK):
                self.write(bytes(bank))
                until = now + len(bank) / per_second
                bank, since = bytearray(), None
            elif not bank:
                until = 0.0

    def write(self, chunk):
        if not chunk:
            return
        with self.player_lock:
            try:
                self.player.stdin.write(chunk)
                self.player.stdin.flush()
            except (OSError, ValueError, AttributeError):
                pass

    def drop_voice(self):
        """She stopped: what the player still holds is thrown away, and a fresh one plays what comes next."""
        self.generation += 1
        with self.player_lock:
            if self.player:
                self.player.kill()
            if not self.closed.is_set():
                self.player = self.new_player()

    def events(self):
        try:
            stream = self.client.call_stream(self.key, 'events')
        except Failed as exc:
            emit(ev='call', type='error', error=str(exc))
            return self.close()
        with stream:
            for line in stream:
                if self.closed.is_set():
                    break
                if not line.startswith(b'data: '):
                    continue
                try:
                    event = json.loads(line[6:])
                except ValueError:
                    continue
                if event.get('type') == 'stop':
                    self.drop_voice()
                emit(ev='call', **event)

    def follow_live(self):
        """While the call runs, what the assistant is doing step by step (`live`): the island shows each step's title and,
        in its little terminal, the search, page or command."""
        try:
            stream = self.client.live_stream()
        except (Failed, AttributeError):
            return
        with stream:
            for line in stream:
                if self.closed.is_set():
                    break
                if line.startswith(b'data: '):
                    try:
                        emit(ev='live', **json.loads(line[6:]))
                    except ValueError:
                        continue

    def close(self):
        if self.closed.is_set():
            return
        self.closed.set()
        for process in (self.recorder, self.player):
            if process:
                process.kill()
        if self.echo:
            self.echo.stop()
        if self.key:
            try:
                self.client.call_close(self.key)
            except Failed:
                pass
        emit(ev='call', type='ended')


class Microphone:
    """One live dictation: the microphone streams to the backend, and the text comes back as it is recognized."""

    def __init__(self, client):
        self.client = client
        self.stopping = threading.Event()
        self.cancelled = False
        self.recorder = None
        self.thread = threading.Thread(target=self.run, daemon=True)
        self.thread.start()

    def stop(self, cancel=False):
        self.cancelled = cancel
        self.stopping.set()
        if cancel:
            if self.recorder:
                self.recorder.terminate()
            return
        # The last word is often still being said when the mic is clicked off, and the recorder holds its newest audio
        # back: it records TAIL seconds more before it stops, so those words are in the final text.
        threading.Timer(TAIL, lambda: self.recorder and self.recorder.terminate()).start()

    def run(self):
        try:
            key = self.client.dictation_open()
        except Failed as exc:
            return emit(ev='dictation', final=True, text='', error=str(exc))
        try:
            recorder = self.recorder = subprocess.Popen(RECORDER, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        except OSError as exc:
            return emit(ev='dictation', final=True, text='', error=f'The microphone could not be opened ({exc})')
        emit(ev='dictation', listening=True, text='')
        last = None
        try:
            if self.stopping.is_set():
                threading.Timer(0 if self.cancelled else TAIL, recorder.terminate).start()
            while True:
                pcm = recorder.stdout.read(CHUNK)
                if not pcm:
                    break
                state = self.client.dictation_feed(key, pcm)
                if state.get('text') != last:
                    last = state.get('text')
                    emit(ev='dictation', text=last or '', settled=state.get('settled') or '', tentative=state.get('tentative') or '')
        except Failed as exc:
            emit(ev='dictation', final=True, text=last or '', error=str(exc))
            recorder.kill()
            return
        finally:
            recorder.terminate()
        try:
            if self.cancelled:
                self.client.dictation_cancel(key)
                return emit(ev='dictation', final=True, cancelled=True, text='')
            result = self.client.dictation_finish(key)
            emit(ev='dictation', final=True, text=result.get('text') or '')
        except Failed as exc:
            emit(ev='dictation', final=True, text=last or '', error=str(exc))


class Bridge:
    def __init__(self):
        self.backend = None
        self.client = None
        self.capabilities = []
        self.lock = threading.Lock()
        self.microphone = None
        self.speaker = None
        self.phone = None

    def connect(self):
        config, problem = load_config()
        backend = pick(config, 'panel')
        self.backend, self.client, self.capabilities = backend, None, []
        if problem or not backend:
            return emit(ev='status', configured=False, connected=False, ready=False,
                        detail=problem or 'No assistant is set up in Settings → AI')
        protocol = PROTOCOLS.get(backend.get('type', 'ai-api'))
        if not protocol:
            return emit(ev='status', configured=True, connected=False, ready=False,
                        detail=f'Tide does not support the "{backend.get("type")}" protocol yet')
        try:
            client = protocol(backend)
            manifest = client.manifest()
        except (Failed, OSError) as exc:
            return emit(ev='status', configured=True, connected=False, ready=False, name=backend.get('name') or '', detail=str(exc))
        self.client = client
        self.capabilities = list(manifest.get('capabilities') or [])
        emit(ev='manifest', backend=backend.get('id') or '', name=manifest.get('name') or backend.get('name') or 'Assistant',
             capabilities=self.capabilities, apps=manifest.get('apps') or [])
        self.check_health()

    def check_health(self):
        if not self.client:
            return
        try:
            # The backend may have been restarted with new features: its manifest is read again each time.
            manifest = self.client.manifest()
            if list(manifest.get('capabilities') or []) != self.capabilities:
                self.capabilities = list(manifest.get('capabilities') or [])
                emit(ev='manifest', backend=(self.backend or {}).get('id') or '', name=manifest.get('name') or 'Assistant',
                     capabilities=self.capabilities, apps=manifest.get('apps') or [])
            health = self.client.health()
            emit(ev='status', configured=True, connected=True, ready=bool(health.get('ready', True)), detail=health.get('detail') or '')
        except Failed as exc:
            emit(ev='status', configured=True, connected=False, ready=False, detail=str(exc))

    def handle(self, request):
        op = request.get('op')
        if op == 'connect':
            return self.connect()
        if op == 'health':
            return self.check_health()
        if not self.client:
            return emit(ev='error', op=op, id=request.get('id'), error='No assistant is connected')
        try:
            if op == 'chats':
                return emit(ev='chats', chats=self.client.chats())
            if op == 'messages':
                return emit(ev='messages', chat=request['chat'], messages=self.client.messages(request['chat']))
            if op == 'send':
                return self.send(request)
            if op == 'cancel':
                return emit(ev='cancelled', chat=request['chat'], result=self.client.cancel(request['chat']))
            if op in ('rename', 'pin'):
                change = dict(title=request['title']) if op == 'rename' else dict(pinned=bool(request['pinned']))
                self.client.update_chat(request['chat'], change)
                return emit(ev='chats', chats=self.client.chats())
            if op == 'delete':
                self.client.delete_chat(request['chat'])
                return emit(ev='chats', chats=self.client.chats())
            if op == 'approvals':
                return emit(ev='approvals', approvals=self.client.approvals(request.get('chat')))
            if op == 'decide':
                self.client.decide(request['approval'], request['decision'], request.get('scope') or 'once', request.get('reason'))
                return emit(ev='approvals', approvals=self.client.approvals())
            if op == 'mode':
                return emit(ev='mode', mode=self.client.mode(request.get('mode')).get('mode'))
            if op == 'app':
                return emit(ev='app', id=request['id'], page=self.client.app(request['id'], request.get('view')))
            if op == 'call':
                with self.lock:
                    action = request.get('action')
                    if action == 'start' and 'voice.call' in self.capabilities:
                        if self.phone:
                            self.phone.close()
                        self.phone = Call(self.client, request.get('source'))
                    elif action == 'mute' and self.phone:
                        self.phone.muted = bool(request.get('on'))
                    elif action == 'end' and self.phone:
                        self.phone.close()
                        self.phone = None
                return
            if op == 'appearance':
                if 'appearance' in self.capabilities:
                    self.client.call('/appearance', 'PUT', request.get('look') or {})
                return
            if op == 'speak':
                with self.lock:
                    if self.speaker:
                        self.speaker.stop()
                        self.speaker = None
                    if not request.get('stop') and request.get('text') and 'voice.speech' in self.capabilities:
                        self.speaker = Speaker(self.client, request['text'])
                    elif request.get('stop'):
                        emit(ev='speech', speaking=False)
                return
            if op == 'check':
                self.client.check(request['app'], request['item'], bool(request.get('done')))
                return emit(ev='app', id=request['app'], page=self.client.app(request['app']))
            if op == 'dictate':
                with self.lock:
                    if request.get('on') and 'voice.dictation' in self.capabilities:
                        if self.microphone:
                            self.microphone.stop(cancel=True)
                        self.microphone = Microphone(self.client)
                    elif self.microphone:
                        self.microphone.stop(cancel=bool(request.get('cancel')))
                        self.microphone = None
                return
            if op == 'power':
                result = self.client.power(request.get('on'))
                return emit(ev='power', on=result.get('on'), state=result.get('state'))
            emit(ev='error', op=op, id=request.get('id'), error=f'Unknown request "{op}"')
        except Failed as exc:
            emit(ev='error', op=op, id=request.get('id'), chat=request.get('chat'), error=str(exc))
        except KeyError as exc:
            emit(ev='error', op=op, id=request.get('id'), error=f'Missing {exc}')

    def send(self, request):
        chat = request['chat']
        emit(ev='reply', chat=chat, type='started')
        try:
            for event in self.client.reply(chat, request['text'], request.get('think'), request.get('attachments')):
                emit(ev='reply', chat=chat, **event)
        except Failed as exc:
            emit(ev='reply', chat=chat, type='error', error=str(exc))
        emit(ev='reply', chat=chat, type='closed')
        self.follow_names()

    def follow_names(self):
        """Backends may name a chat (or change other chats) a little after a reply ends: the list is re-read a few times and
        sent again whenever it changed, so a new name shows in the sidebar and the header without a reload."""
        if 'history' not in self.capabilities:
            return
        last = None
        for wait in (1, 2, 3, 4, 5, 6, 8, 10):
            time.sleep(wait)
            try:
                chats = self.client.chats()
            except Failed:
                return
            if chats != last:
                emit(ev='chats', chats=chats)
            last = chats


def main():
    EchoCancel.clear_leftovers()
    bridge = Bridge()
    bridge.connect()

    def poll():
        while True:
            time.sleep(HEALTH_EVERY)
            if bridge.client:
                bridge.check_health()
            else:
                bridge.connect()
    threading.Thread(target=poll, daemon=True).start()
    for line in sys.stdin:
        try:
            request = json.loads(line)
        except ValueError:
            continue
        if isinstance(request, dict):
            # Replies stream for minutes; everything runs on its own thread so the shell never waits on one.
            threading.Thread(target=bridge.handle, args=(request,), daemon=True).start()


if __name__ == '__main__':
    main()
