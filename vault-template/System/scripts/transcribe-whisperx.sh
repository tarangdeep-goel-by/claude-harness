#!/bin/bash
# transcribe-whisperx.sh — Transcribe audio with speaker diarization using WhisperX
#
# Usage:
#   transcribe-whisperx.sh <audio-file>                    # Auto output path
#   transcribe-whisperx.sh <audio-file> <output-path>      # Custom output
#   transcribe-whisperx.sh <audio-file> --no-diarize       # Skip diarization
#
# Requires: HF_TOKEN env var or .env file (for pyannote gated models)
# Supports: m4a, mp3, wav, ogg, aac, mp4, webm

set -euo pipefail

VENV="$HOME/Documents/vault-work/System/venvs/whisper-mlx"
MODEL="${WHISPERX_MODEL:-large-v3-turbo}"
THREADS="${WHISPERX_THREADS:-8}"

if [ $# -lt 1 ]; then
  echo "Usage: transcribe-whisperx.sh <audio-file> [output-path] [--no-diarize]"
  exit 1
fi

INPUT="$1"
BASENAME="${INPUT%.*}"
DIARIZE=true

# Parse args
OUTPUT=""
for arg in "${@:2}"; do
  if [ "$arg" = "--no-diarize" ]; then
    DIARIZE=false
  else
    OUTPUT="$arg"
  fi
done

OUTPUT="${OUTPUT:-${BASENAME}_transcript_whisperx.json}"

if [ ! -f "$INPUT" ]; then
  echo "Error: File not found: $INPUT"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
[ -f "$SCRIPT_DIR/.env" ] && export $(grep -v '^#' "$SCRIPT_DIR/.env" | xargs)

if [ -z "${HF_TOKEN:-}" ]; then
  echo "Error: HF_TOKEN not set. Get one from https://huggingface.co/settings/tokens"
  exit 1
fi

source "$VENV/bin/activate"

echo "==> WhisperX (model: $MODEL, diarize: $DIARIZE, threads: $THREADS)"
echo "==> Input: $INPUT"
echo ""

export _WX_INPUT="$INPUT"
export _WX_OUTPUT="$OUTPUT"
export _WX_DIARIZE="$DIARIZE"
export _WX_MODEL="$MODEL"
export _WX_THREADS="$THREADS"
export OMP_NUM_THREADS="$THREADS"
export MKL_NUM_THREADS="$THREADS"
export PYTHONWARNINGS="ignore::UserWarning"

START=$(date +%s)

python3 << 'PYEOF'
import warnings
warnings.filterwarnings('ignore')
import logging
logging.disable(logging.INFO)

import whisperx, json, os, sys, time, gc

hf_token = os.environ['HF_TOKEN']
audio_file = os.environ['_WX_INPUT']
output_file = os.environ['_WX_OUTPUT']
diarize = os.environ.get('_WX_DIARIZE', 'true') == 'true'
model_name = os.environ.get('_WX_MODEL', 'large-v3-turbo')
threads = int(os.environ.get('_WX_THREADS', '8'))

import torch
use_mps = torch.backends.mps.is_available()
torch_device = 'mps' if use_mps else 'cpu'
ct2_device = 'cpu'  # CTranslate2 has no MPS support

total_start = time.time()

# ─── Progress bar helper ───
def progress_bar(pct, width=40, label=''):
    filled = int(width * pct / 100)
    bar = '█' * filled + '░' * (width - filled)
    sys.stdout.write(f'\r       [{bar}] {pct:5.1f}% {label}')
    sys.stdout.flush()

def progress_done(msg):
    sys.stdout.write(f'\r       {msg}' + ' ' * 40 + '\n')
    sys.stdout.flush()

# ─── Step 1: Load audio ───
print(f'[1/4] Loading audio...', end=' ', flush=True)
t0 = time.time()
audio = whisperx.load_audio(audio_file)
duration_sec = len(audio) / 16000
duration_min = duration_sec / 60
print(f'{duration_min:.1f} min audio [{time.time()-t0:.1f}s]')

# ─── Step 2: Transcribe (CPU — CTranslate2) ───
print(f'[2/4] Transcribing (device={ct2_device}, threads={threads})')
t1 = time.time()
print(f'       loading model...', end='', flush=True)
model = whisperx.load_model(model_name, ct2_device, compute_type='int8', threads=threads)
t_model = time.time()
print(f' done [{t_model-t1:.0f}s]')

print(f'       running VAD + language detect...', end='', flush=True)

# Transcription progress callback
t_transcribe_start = [None]
def transcribe_progress(pct):
    if t_transcribe_start[0] is None:
        t_transcribe_start[0] = time.time()
        # Clear the VAD line
        sys.stdout.write('\r' + ' ' * 60 + '\r')
        sys.stdout.flush()
    elapsed = time.time() - t_transcribe_start[0]
    if pct > 0:
        eta = elapsed * (100 - pct) / pct
        eta_str = f'ETA {eta/60:.0f}m' if eta > 60 else f'ETA {eta:.0f}s'
    else:
        eta_str = ''
    progress_bar(pct, label=eta_str)

result = model.transcribe(audio, batch_size=16, print_progress=False, progress_callback=transcribe_progress)
t2 = time.time()
n_segs = len(result['segments'])
lang = result['language']
speed = duration_sec / (t2 - t1)
progress_done(f'done ({n_segs} segments, lang={lang}, {speed:.1f}x realtime) [{t2-t1:.0f}s]')

# Save checkpoint
cp = output_file.replace('.json', '_step2.json')
with open(cp, 'w') as f:
    json.dump(result, f, indent=2, ensure_ascii=False)

del model
if use_mps: torch.mps.empty_cache()
gc.collect()

# ─── Step 3: Align (MPS if available) ───
print(f'[3/4] Aligning words (device={torch_device})...', end=' ', flush=True)
t3 = time.time()
model_a, metadata = whisperx.load_align_model(language_code=lang, device=torch_device)
result = whisperx.align(result['segments'], model_a, metadata, audio, torch_device, return_char_alignments=False)
t4 = time.time()
print(f'done [{t4-t3:.0f}s]')

cp = output_file.replace('.json', '_aligned.json')
with open(cp, 'w') as f:
    json.dump(result, f, indent=2, ensure_ascii=False)

del model_a
if use_mps: torch.mps.empty_cache()
gc.collect()

# ─── Step 4: Diarize (MPS if available) ───
if diarize:
    print(f'[4/4] Diarizing speakers (device={torch_device})')
    t5 = time.time()
    from whisperx.diarize import DiarizationPipeline

    def diarize_progress(pct):
        elapsed = time.time() - t5
        if pct > 0:
            eta = elapsed * (100 - pct) / pct
            eta_str = f'ETA {eta/60:.0f}m' if eta > 60 else f'ETA {eta:.0f}s'
        else:
            eta_str = ''
        progress_bar(pct, label=eta_str)

    diarize_model = DiarizationPipeline(token=hf_token, device=torch_device)
    diarize_segments = diarize_model(audio, progress_callback=diarize_progress)
    result = whisperx.assign_word_speakers(diarize_segments, result)

    speakers = set()
    for seg in result['segments']:
        if 'speaker' in seg:
            speakers.add(seg['speaker'])

    t6 = time.time()
    progress_done(f'done ({len(speakers)} speakers) [{t6-t5:.0f}s]')

    del diarize_model
    if use_mps: torch.mps.empty_cache()
    gc.collect()
else:
    print('[4/4] Diarization skipped (--no-diarize)')

# ─── Save outputs ───
print()

# Slim JSON — drop word-level data and logprobs, keep segment-level only
slim_segments = []
for seg in result['segments']:
    slim_segments.append({
        'start': seg.get('start'),
        'end': seg.get('end'),
        'text': seg.get('text', '').strip(),
        'speaker': seg.get('speaker', 'UNKNOWN'),
    })
slim_result = {
    'segments': slim_segments,
    'language': result.get('language', lang),
}
with open(output_file, 'w') as f:
    json.dump(slim_result, f, indent=2, ensure_ascii=False)
print(f'  Saved: {output_file}')

txt_file = output_file.replace('.json', '.txt')
with open(txt_file, 'w') as f:
    current_speaker = None
    for seg in result['segments']:
        speaker = seg.get('speaker', 'UNKNOWN')
        start = seg.get('start', 0)
        end = seg.get('end', 0)
        text = seg.get('text', '').strip()
        if diarize:
            if speaker != current_speaker:
                f.write(f'\n[{speaker}] ({start:.1f}s - {end:.1f}s)\n')
                current_speaker = speaker
            else:
                f.write(f'({start:.1f}s) ')
        else:
            f.write(f'[{start:.1f}s - {end:.1f}s] ')
        f.write(f'{text}\n')
print(f'  Saved: {txt_file}')

# Clean up checkpoints
for suffix in ['_step2.json', '_aligned.json']:
    cp = output_file.replace('.json', suffix)
    if os.path.exists(cp):
        os.remove(cp)

# ─── Summary ───
total = time.time() - total_start
print()
print(f'  ┌─────────────────────────────┐')
print(f'  │ Audio:  {duration_min:5.1f} min            │')
print(f'  │ Total:  {total:5.0f}s ({total/60:.1f} min)      │')
print(f'  │ Speed:  {duration_sec/total:5.1f}x realtime      │')
print(f'  │ Device: {torch_device:>4s} (align+diarize) │')
print(f'  └─────────────────────────────┘')
PYEOF

END=$(date +%s)
ELAPSED=$((END - START))
echo ""
echo "==> Complete (${ELAPSED}s)"
