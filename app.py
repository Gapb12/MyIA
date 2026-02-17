# ==========================================================
# ECHO TUTOR - EXTREME PEDAGOGICAL VERSION
# ==========================================================

import os
import json
import time
import sqlite3
import threading
from datetime import datetime, timedelta
from enum import Enum

import gradio as gr
from thefuzz import fuzz
from faster_whisper import WhisperModel
from llama_cpp import Llama
import subprocess

# ==========================================================
# 1️⃣ CONFIGURAÇÕES GLOBAIS
# ==========================================================

LLM_MODEL_PATH = "models/llama-3-8b.gguf"
WHISPER_MODEL_SIZE = "small.en"
PIPER_PATH = "models/piper/piper"
PIPER_VOICE = "models/piper/en_US-amy-medium.onnx"

DB_PATH = "echo_tutor.db"
CONFIDENCE_THRESHOLD = -0.6
FUZZ_THRESHOLD = 90

LLM_IDLE_TIMEOUT = 300  # 5 minutos

# ==========================================================
# 2️⃣ ESTADOS DO SISTEMA
# ==========================================================

class TutorState(Enum):
    ASSESSMENT = 1
    LESSON = 2
    ERROR_FEEDBACK = 3
    IMMEDIATE_DRILL = 4
    SRS_REVIEW = 5
    LEVEL_UPDATE = 6

current_state = TutorState.ASSESSMENT

# ==========================================================
# 3️⃣ INICIALIZAÇÃO MODELOS
# ==========================================================

whisper = WhisperModel(WHISPER_MODEL_SIZE, compute_type="int8")

llm = None
last_llm_use = time.time()

def load_llm():
    global llm
    if llm is None:
        llm = Llama(
            model_path=LLM_MODEL_PATH,
            n_ctx=2048,
            n_threads=os.cpu_count(),
            n_gpu_layers=0
        )

def unload_llm():
    global llm
    llm = None

def llm_idle_monitor():
    while True:
        if llm and (time.time() - last_llm_use > LLM_IDLE_TIMEOUT):
            unload_llm()
        time.sleep(30)

threading.Thread(target=llm_idle_monitor, daemon=True).start()

# ==========================================================
# 4️⃣ BANCO DE DADOS
# ==========================================================

def init_db():
    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()

    c.execute("""
    CREATE TABLE IF NOT EXISTS learning_logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
        user_input TEXT,
        corrected_version TEXT,
        error_type TEXT,
        review_count INTEGER DEFAULT 0,
        next_review_date DATETIME,
        easiness REAL DEFAULT 2.5,
        interval INTEGER DEFAULT 1,
        repetitions INTEGER DEFAULT 0,
        status TEXT DEFAULT 'ACTIVE'
    );
    """)

    conn.commit()
    conn.close()

init_db()

# ==========================================================
# 5️⃣ SRS ENGINE (SuperMemo-2 Simplificado)
# ==========================================================

def calculate_srs(log_id, quality):
    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()

    c.execute("SELECT easiness, interval, repetitions FROM learning_logs WHERE id=?", (log_id,))
    easiness, interval, repetitions = c.fetchone()

    if quality < 3:
        repetitions = 0
        interval = 1
    else:
        repetitions += 1
        if repetitions == 1:
            interval = 1
        elif repetitions == 2:
            interval = 3
        else:
            interval = round(interval * easiness)

    easiness = max(1.3, easiness + (0.1 - (5-quality)*(0.08+(5-quality)*0.02)))
    next_review = datetime.now() + timedelta(days=interval)

    c.execute("""
    UPDATE learning_logs
    SET easiness=?, interval=?, repetitions=?, review_count=review_count+1,
        next_review_date=?
    WHERE id=?
    """, (easiness, interval, repetitions, next_review, log_id))

    conn.commit()
    conn.close()

# ==========================================================
# 6️⃣ STT + VALIDAÇÃO DE CONFIANÇA
# ==========================================================

def transcribe(audio_path):
    segments, _ = whisper.transcribe(audio_path)
    text = ""
    avg_conf = 0
    count = 0

    for segment in segments:
        text += segment.text
        avg_conf += segment.avg_logprob
        count += 1

    avg_conf /= max(count, 1)

    return text.strip(), avg_conf

# ==========================================================
# 7️⃣ LLM CLASSIFICADOR
# ==========================================================

SYSTEM_PROMPT = """You are a strict English Tutor.
Return ONLY JSON:
{
"reply": "string",
"has_error": bool,
"correction": "string",
"error_type": "grammar|pronunciation|vocab",
"explanation": "string"
}"""

def analyze_text(text):
    global last_llm_use
    load_llm()
    last_llm_use = time.time()

    response = llm.create_chat_completion(
        messages=[
            {"role": "system", "content": SYSTEM_PROMPT},
            {"role": "user", "content": text}
        ],
        temperature=0.2
    )

    content = response["choices"][0]["message"]["content"]
    return json.loads(content)

# ==========================================================
# 8️⃣ MOTOR PEDAGÓGICO
# ==========================================================

def pedagogical_engine(audio):
    global current_state

    text, confidence = transcribe(audio)

    if confidence < CONFIDENCE_THRESHOLD:
        return "Speak more clearly. Repeat.", None

    result = analyze_text(text)

    if result["has_error"]:
        save_error(text, result["correction"], result["error_type"])
        current_state = TutorState.IMMEDIATE_DRILL
        return f"Correction: {result['correction']}", result["correction"]

    current_state = TutorState.LESSON
    return result["reply"], None

# ==========================================================
# 9️⃣ SALVAR ERROS
# ==========================================================

def save_error(user_input, corrected, error_type):
    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()

    c.execute("""
    INSERT INTO learning_logs (user_input, corrected_version,
    error_type, next_review_date)
    VALUES (?, ?, ?, ?)
    """, (user_input, corrected, error_type, datetime.now()))

    conn.commit()
    conn.close()

# ==========================================================
# 🔟 TTS STREAM
# ==========================================================

def speak(text):
    process = subprocess.Popen(
        [PIPER_PATH, "-m", PIPER_VOICE],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE
    )
    process.stdin.write(text.encode())
    process.stdin.close()
    return process.stdout.read()

# ==========================================================
# 11️⃣ GRADIO UI
# ==========================================================

def interface(audio):
    reply, correction = pedagogical_engine(audio)

    audio_output = speak(reply)
    return reply, audio_output

with gr.Blocks() as demo:
    gr.Markdown("# Echo Tutor - Extreme Mode")

    audio_input = gr.Audio(type="filepath")
    text_output = gr.Textbox()
    audio_response = gr.Audio()

    audio_input.change(interface, inputs=audio_input,
                       outputs=[text_output, audio_response])

demo.launch(server_name="0.0.0.0")
