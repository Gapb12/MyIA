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
import time
import gc
from thefuzz import fuzz

# ================= CONFIG =================
MODEL_PATH = "models/llama-3-8b.gguf"
PIPER_BINARY = "./models/piper/piper"
VOICE_MODEL = "models/piper/en_US-amy-medium.onnx"
DB_NAME = "echo_tutor.db"

LLM_IDLE_TIMEOUT = 300  # 5 minutos
last_llm_use = time.time()
llm = None

# ================= DATABASE =================
conn = sqlite3.connect(DB_NAME, check_same_thread=False)
c = conn.cursor()

c.execute("""
CREATE TABLE IF NOT EXISTS learning_logs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
    user_input TEXT,
    corrected_version TEXT,
    error_type TEXT,
    explanation TEXT,
    review_count INTEGER DEFAULT 0,
    next_review_date DATETIME,
    status TEXT DEFAULT 'ACTIVE'
);
""")
conn.commit()

# ================= MODELS =================
print("Loading Whisper...")
whisper = WhisperModel("base.en", device="cpu", compute_type="int8")

def load_llm():
    global llm, last_llm_use
    if llm is None:
        print("Loading LLM...")
        llm = Llama(
            model_path=MODEL_PATH,
            n_ctx=2048,
            n_gpu_layers=0,
            verbose=False
        )
    last_llm_use = time.time()

def check_llm_idle():
    global llm
    if llm and time.time() - last_llm_use > LLM_IDLE_TIMEOUT:
        print("Unloading LLM (idle)...")
        llm = None
        gc.collect()

# ================= UTILS =================
def falar_piper(texto):
    texto = re.sub(r'[^a-zA-Z0-9 .,?!]', '', texto)
    output_file = f"temp_{int(time.time())}.wav"

    cmd = f'echo "{texto}" | {PIPER_BINARY} --model {VOICE_MODEL} --output_file {output_file}'
    subprocess.run(cmd, shell=True)

    return output_file

def normalizar(texto):
    texto = texto.lower()
    texto = re.sub(r'[^\w\s]', '', texto)
    texto = re.sub(r'\s+', ' ', texto).strip()
    return texto

def calcular_proxima_revisao(review_count):
    intervals = [1, 3, 7, 14, 30]
    days = intervals[min(review_count, len(intervals)-1)]
    return datetime.datetime.now() + datetime.timedelta(days=days)

# ================= CORE =================
def analisar_conversa(audio_path):
    try:
        check_llm_idle()

        if not audio_path:
            return "No audio.", None

        segments, _ = whisper.transcribe(audio_path, beam_size=5)
        segments = list(segments)

        if not segments:
            return "No speech detected.", None

        avg_logprob = sum(s.avg_logprob for s in segments) / len(segments)

        if avg_logprob < -0.6:
            return "⚠️ Speak more clearly.", falar_piper("Please speak more clearly.")

        user_text = " ".join(s.text for s in segments).strip()

        load_llm()

        system_prompt = """
You are a strict English Tutor.
Return ONLY valid JSON with this exact schema:
{
 "reply": "string",
 "has_error": true/false,
 "correction": "string",
 "error_type": "grammar|pronunciation|vocab",
 "explanation": "string"
}
Do not write anything outside the JSON.
"""

        prompt = f"""<|begin_of_text|>
<|start_header_id|>system<|end_header_id|>
{system_prompt}
<|eot_id|>
<|start_header_id|>user<|end_header_id|>
{user_text}
<|eot_id|>
<|start_header_id|>assistant<|end_header_id|>
"""

        output = llm(
            prompt,
            max_tokens=256,
            temperature=0.0,
            stop=["<|eot_id|>"],
            echo=False
        )

        raw = output['choices'][0]['text']
        json_str = raw[raw.find('{'):raw.rfind('}')+1]
        data = json.loads(json_str)

        reply = data["reply"]

        if data["has_error"]:
            correction = data["correction"]
            explanation = data["explanation"]

            next_review = calcular_proxima_revisao(0)

            c.execute("""
            INSERT INTO learning_logs 
            (user_input, corrected_version, error_type, explanation, next_review_date)
            VALUES (?, ?, ?, ?, ?)
            """, (user_text, correction, data["error_type"], explanation, next_review))
            conn.commit()

            reply += f"\n\n🛑 Correction: {correction}"

        return f"You: {user_text}\nAI: {reply}", falar_piper(reply)

    except Exception as e:
        return f"Error: {str(e)}", None


# ================= REVIEW MODE =================
def carregar_exercicio():
    c.execute("""
    SELECT id, user_input, corrected_version, explanation
    FROM learning_logs
    WHERE next_review_date <= datetime('now')
    AND status='ACTIVE'
    ORDER BY next_review_date ASC
    LIMIT 1
    """)

    row = c.fetchone()

    if not row:
        return "No pending reviews 🎉", None, None

    id_log, original, correcao, explicacao = row

    return (
        f"Said: {original}\nCorrect: {correcao}\nTip: {explicacao}",
        falar_piper(f"Repeat: {correcao}"),
        id_log
    )

def validar_exercicio(audio_path, id_log):
    if not audio_path or not id_log:
        return "Record first.", None

    segments, _ = whisper.transcribe(audio_path)
    tentativa = " ".join(s.text for s in segments).strip()

    c.execute("SELECT corrected_version, review_count FROM learning_logs WHERE id = ?", (id_log,))
    row = c.fetchone()

    if not row:
        return "Data error.", None

    correto, review_count = row

    ratio = fuzz.ratio(normalizar(tentativa), normalizar(correto))

    if ratio > 90:
        novo_count = review_count + 1
        proxima = calcular_proxima_revisao(novo_count)

        c.execute("""
        UPDATE learning_logs
        SET review_count=?, next_review_date=?
        WHERE id=?
        """, (novo_count, proxima, id_log))
        conn.commit()

        return f"✅ Excellent ({ratio}%)", falar_piper("Perfect!")

    else:
        return f"❌ Try again ({ratio}%)", falar_piper("Try again.")

# ================= UI =================
with gr.Blocks(title="Echo Tutor Pro") as demo:
    gr.Markdown("# Echo Tutor Pro")

    with gr.Tabs():
        with gr.TabItem("Conversation"):
            inp = gr.Audio(sources=["microphone"], type="filepath")
            out_txt = gr.Textbox()
            out_aud = gr.Audio(autoplay=True)
            gr.Button("Send").click(analisar_conversa, inp, [out_txt, out_aud])

        with gr.TabItem("Review"):
            btn_load = gr.Button("Load Next")
            id_h = gr.Number(visible=False)
            lbl = gr.Textbox()
            aud_ref = gr.Audio(autoplay=True)
            inp_drill = gr.Audio(sources=["microphone"], type="filepath")
            res_txt = gr.Textbox()
            res_aud = gr.Audio(autoplay=True)
            btn_check = gr.Button("Check")

            btn_load.click(carregar_exercicio, None, [lbl, aud_ref, id_h])
            btn_check.click(validar_exercicio, [inp_drill, id_h], [res_txt, res_aud])

if __name__ == "__main__":
    demo.launch(server_name="0.0.0.0", server_port=7860)
