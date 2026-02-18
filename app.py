import gradio as gr
from faster_whisper import WhisperModel
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
DB_NAME = "echo_tutor.db"
SIMILARITY_THRESHOLD = 90

# DATABASE
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
    next_review_date DATETIME
)
""")
conn.commit()

# MODELS
whisper_model = WhisperModel("base.en", device="cpu", compute_type="int8")
llm = Llama(
    model_path=MODEL_PATH,
    n_ctx=2048,
    n_threads=4,
    n_batch=512,
    n_gpu_layers=0,
    verbose=True
)

# TTS
def falar(texto):
    texto = re.sub(r'[^a-zA-Z0-9 .,?!]', '', texto)
    file = f"tts_{int(datetime.datetime.now().timestamp())}.wav"
    cmd = f'echo "{texto}" | {PIPER_BINARY} --model {VOICE_MODEL} --output_file {file}'
    try:
        subprocess.run(cmd, shell=True, check=True)
        return file
    except subprocess.CalledProcessError as e:
        print(f"Erro no Piper: {e}")
        return None

# ANALYSIS
def analisar(audio_path):
    if not audio_path:
        return "No audio.", None
    segments, info = whisper_model.transcribe(audio_path)
    user_text = " ".join(segment.text.strip() for segment in segments)
    print(f"Transcrito: {user_text}")
    system_prompt = """
You are a strict English tutor.
Return ONLY JSON:
{
  "reply": "",
  "has_error": true/false,
  "correction": "",
  "error_type": "",
  "sub_type": "",
  "explanation": ""
}
"""
    prompt = f"{system_prompt}\nUser: {user_text}\nAssistant:"
    try:
        output = llm(prompt, max_tokens=256, stop=["}"])
        raw = output['choices'][0]['text']
        data = json.loads(raw + "}" if not raw.endswith("}") else raw)  # Fix JSON incompleto
    except Exception as e:
        print(f"Erro no LLM: {e}")
        return str(e), None
    reply = data["reply"]
    if data["has_error"]:
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
            datetime.datetime.now() + datetime.timedelta(days=1)
        ))
        conn.commit()
        reply += f"\nCorrection: {data['correction']}"
    return f"You: {user_text}\nAI: {reply}", falar(reply)

# UI com aba para Drill (simples)
def review_errors():
    c.execute("SELECT * FROM learning_logs WHERE next_review_date <= DATETIME('now')")
    errors = c.fetchall()
    if not errors:
        return "No errors to review."
    reply = ""
    for error in errors:
        reply += f"User: {error[2]}\nCorrection: {error[3]}\nExplanation: {error[6]}\n---\n"
    return reply, falar(reply)

with gr.Blocks(title="Echo Tutor") as demo:
    gr.Markdown("# Echo Tutor – Adaptive English")
    with gr.Tab("Conversação"):
        inp = gr.Audio(sources=["microphone"], type="filepath")
        out_txt = gr.Textbox()
        out_aud = gr.Audio(autoplay=True)
        gr.Button("Send").click(analisar, inp, [out_txt, out_aud])
    with gr.Tab("Review Erros"):
        review_btn = gr.Button("Carregar Erros")
        review_txt = gr.Textbox()
        review_aud = gr.Audio(autoplay=True)
        review_btn.click(review_errors, outputs=[review_txt, review_aud])

if __name__ == "__main__":
    demo.launch(server_name="0.0.0.0", server_port=7860)
