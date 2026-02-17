import gradio as gr
from faster_whisper import WhisperModel
from llama_cpp import Llama
import subprocess
import json
import sqlite3
import datetime
import os
import re
import traceback
from thefuzz import fuzz

# ==========================
# CONFIG
# ==========================

MODEL_PATH = "models/llama-3-8b.gguf"
PIPER_BINARY = "./models/piper/piper"
VOICE_MODEL = "models/piper/en_US-amy-medium.onnx"
DB_NAME = "echo_tutor.db"

PRON_THRESHOLD = -0.6
SIMILARITY_THRESHOLD = 90

# ==========================
# DATABASE
# ==========================

conn = sqlite3.connect(DB_NAME, check_same_thread=False)
c = conn.cursor()

c.execute("""
CREATE TABLE IF NOT EXISTS learning_logs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
    user_input TEXT,
    corrected_version TEXT,
    error_type TEXT,
    sub_type TEXT,
    explanation TEXT,
    review_count INTEGER DEFAULT 0,
    next_review_date DATETIME,
    status TEXT DEFAULT 'ACTIVE'
)
""")

c.execute("""
CREATE TABLE IF NOT EXISTS error_stats (
    error_type TEXT,
    sub_type TEXT,
    total_occurrences INTEGER DEFAULT 0,
    last_occurrence DATETIME,
    successful_reviews INTEGER DEFAULT 0,
    PRIMARY KEY (error_type, sub_type)
)
""")

conn.commit()

# ==========================
# LOAD MODELS
# ==========================

whisper = WhisperModel("small.en", device="cpu", compute_type="int8")

llm = Llama(
    model_path=MODEL_PATH,
    n_ctx=2048,
    n_gpu_layers=-1,
    verbose=False
)

# ==========================
# UTILITIES
# ==========================

def falar(texto):
    texto = re.sub(r'[^a-zA-Z0-9 .,?!]', '', texto)
    file = f"tts_{int(datetime.datetime.now().timestamp())}.wav"
    cmd = f'echo "{texto}" | {PIPER_BINARY} --model {VOICE_MODEL} --output_file {file}'
    subprocess.run(cmd, shell=True)
    return file

def calcular_proxima_revisao(count):
    intervals = [1, 3, 7, 14, 30]
    days = intervals[min(count, len(intervals)-1)]
    return datetime.datetime.now() + datetime.timedelta(days=days)

# ==========================
# ERROR STAT ENGINE
# ==========================

def atualizar_estatisticas(error_type, sub_type):
    c.execute("""
    INSERT INTO error_stats (error_type, sub_type, total_occurrences, last_occurrence)
    VALUES (?, ?, 1, CURRENT_TIMESTAMP)
    ON CONFLICT(error_type, sub_type)
    DO UPDATE SET
        total_occurrences = total_occurrences + 1,
        last_occurrence = CURRENT_TIMESTAMP
    """, (error_type, sub_type))
    conn.commit()

def registrar_sucesso(error_type, sub_type):
    c.execute("""
    UPDATE error_stats
    SET successful_reviews = successful_reviews + 1
    WHERE error_type = ? AND sub_type = ?
    """, (error_type, sub_type))
    conn.commit()

def calcular_fragility():
    c.execute("""
    SELECT error_type, sub_type,
           total_occurrences,
           successful_reviews
    FROM error_stats
    """)
    rows = c.fetchall()

    scores = []
    for row in rows:
        total = row[2]
        success = row[3]
        score = (total * 1.5) - (success * 1)
        scores.append((row[0], row[1], score))

    if not scores:
        return None, None

    scores.sort(key=lambda x: x[2], reverse=True)
    return scores[0][0], scores[0][1]

# ==========================
# CORE ANALYSIS
# ==========================

def analisar(audio_path):
    if not audio_path:
        return "No audio.", None

    segments, _ = whisper.transcribe(audio_path)
    text_parts = []

    for s in segments:
        if s.avg_logprob < PRON_THRESHOLD:
            return "Pronunciation unclear. Repeat.", falar("Speak clearly.")
        text_parts.append(s.text)

    user_text = " ".join(text_parts).strip()

    error_focus_type, error_focus_sub = calcular_fragility()

    adaptive_hint = ""
    if error_focus_sub:
        adaptive_hint = f"The student struggles with {error_focus_sub}. Force practice involving this."

    system_prompt = f"""
You are a strict English Tutor.
{adaptive_hint}
Return ONLY JSON:
{{
  "reply": "string",
  "has_error": true/false,
  "correction": "string",
  "error_type": "grammar|vocab|pronunciation",
  "sub_type": "specific_category",
  "explanation": "string"
}}
"""

    prompt = f"<|begin_of_text|><|start_header_id|>system<|end_header_id|>\n{system_prompt}\n<|eot_id|><|start_header_id|>user<|end_header_id|>\n{user_text}\n<|eot_id|><|start_header_id|>assistant<|end_header_id|>\n"

    output = llm(prompt, max_tokens=256, stop=["<|eot_id|>"])
    raw = output['choices'][0]['text']

    try:
        data = json.loads(raw[raw.find("{"):raw.rfind("}")+1])
    except:
        return raw, falar(raw)

    reply = data["reply"]

    if data["has_error"]:
        atualizar_estatisticas(data["error_type"], data["sub_type"])

        c.execute("""
        INSERT INTO learning_logs
        (user_input, corrected_version, error_type, sub_type, explanation, next_review_date)
        VALUES (?, ?, ?, ?, ?, ?)
        """, (
            user_text,
            data["correction"],
            data["error_type"],
            data["sub_type"],
            data["explanation"],
            datetime.datetime.now()
        ))
        conn.commit()

        reply += f"\n\nCorrection: {data['correction']}"

    return f"You: {user_text}\nAI: {reply}", falar(reply)

# ==========================
# SMART DRILL
# ==========================

def carregar_drill():
    c.execute("""
    SELECT id, user_input, corrected_version, error_type, sub_type
    FROM learning_logs
    WHERE next_review_date <= datetime('now')
    ORDER BY next_review_date ASC
    LIMIT 1
    """)

    row = c.fetchone()

    if not row:
        return "No pending reviews.", None, None

    return (
        f"Said: {row[1]}\nCorrect: {row[2]}",
        falar(f"Repeat: {row[2]}"),
        row[0]
    )

def validar_drill(audio_path, id_log):
    if not audio_path:
        return "Record first.", None

    segments, _ = whisper.transcribe(audio_path)
    tentativa = " ".join([s.text for s in segments]).strip()

    c.execute("""
    SELECT corrected_version, review_count, error_type, sub_type
    FROM learning_logs WHERE id = ?
    """, (id_log,))
    row = c.fetchone()

    if not row:
        return "Error.", None

    correto, review_count, e_type, sub = row
    ratio = fuzz.ratio(tentativa.lower(), correto.lower())

    if ratio >= SIMILARITY_THRESHOLD:
        novo = review_count + 1
        proxima = calcular_proxima_revisao(novo)

        c.execute("""
        UPDATE learning_logs
        SET review_count = ?, next_review_date = ?
        WHERE id = ?
        """, (novo, proxima, id_log))

        registrar_sucesso(e_type, sub)

        conn.commit()
        return "Excellent.", falar("Excellent.")
    else:
        return f"Try again ({ratio}%).", falar("Try again.")

# ==========================
# DASHBOARD
# ==========================

def estatisticas():
    c.execute("""
    SELECT sub_type, total_occurrences, successful_reviews
    FROM error_stats
    ORDER BY total_occurrences DESC
    """)
    rows = c.fetchall()

    if not rows:
        return "No data yet."

    report = ""
    for r in rows:
        report += f"{r[0]} → Errors: {r[1]} | Success: {r[2]}\n"

    return report

# ==========================
# UI
# ==========================

with gr.Blocks(title="Echo Tutor Extreme") as demo:
    gr.Markdown("# Echo Tutor – Adaptive Intelligence")

    with gr.Tab("Conversation"):
        inp = gr.Audio(sources=["microphone"], type="filepath")
        out_txt = gr.Textbox()
        out_aud = gr.Audio(autoplay=True)
        gr.Button("Send").click(analisar, inp, [out_txt, out_aud])

    with gr.Tab("Drill"):
        btn = gr.Button("Load")
        id_hidden = gr.Number(visible=False)
        lbl = gr.Textbox()
        aud_ref = gr.Audio(autoplay=True)
        inp2 = gr.Audio(sources=["microphone"], type="filepath")
        res = gr.Textbox()
        aud2 = gr.Audio(autoplay=True)
        gr.Button("Check").click(validar_drill, [inp2, id_hidden], [res, aud2])
        btn.click(carregar_drill, None, [lbl, aud_ref, id_hidden])

    with gr.Tab("Stats"):
        stats_btn = gr.Button("Refresh")
        stats_box = gr.Textbox()
        stats_btn.click(estatisticas, None, stats_box)

if __name__ == "__main__":
    demo.launch(server_name="0.0.0.0", server_port=7860)
