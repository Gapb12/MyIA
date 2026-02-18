import gradio as gr
from llama_cpp import Llama
import subprocess
import json
import sqlite3
import datetime
import re
from thefuzz import fuzz

MODEL_PATH = "models/llama-3-3b.gguf"
PIPER_BINARY = "./models/piper/piper"
VOICE_MODEL = "models/piper/en_US-amy-medium.onnx"
WHISPER_CPP = "~/whisper.cpp/build/bin/main"  # Path para o executável whisper.cpp
WHISPER_MODEL = "~/whisper.cpp/models/ggml-base.en.bin"
DB_NAME = "echo_tutor.db"
SIMILARITY_THRESHOLD = 90

# DATABASE (mesmo)

# MODELS (LLM mesmo)

# TTS (mesmo)

# STT com whisper.cpp
def analisar(audio_path):
    if not audio_path:
        return "No audio.", None
    # Converta para 16kHz WAV se necessário
    wav_path = "temp.wav"
    subprocess.run(["ffmpeg", "-y", "-i", audio_path, "-ar", "16000", "-ac", "1", wav_path], check=True)
    # Transcreva com whisper.cpp
    result = subprocess.run([WHISPER_CPP, "-m", WHISPER_MODEL, "-f", wav_path, "-l", "en"], capture_output=True, text=True)
    user_text = result.stdout.strip()
    print(f"Transcrito: {user_text}")
    # resto do código igual (prompt LLM, DB, TTS)

# UI (mesmo)

if __name__ == "__main__":
    demo.launch(server_name="0.0.0.0", server_port=7860)
