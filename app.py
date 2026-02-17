import gradio as gr
import whisper
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
whisper_model = whisper.load_model("base.en")

llm = Llama(
    model_path=MODEL_PATH,
    n_ctx=4096,
    n_threads=8,
    n_batch=512,
    n_gpu_layers=0,
    verbose=False
)

# TTS
def falar(texto):
    texto = re.sub(r'[^a-zA-Z0-9 .,?!]', '', texto)
    file = f"tts_{int(datetime.datetime.now().timestamp())}.wav"
    cmd = f'echo "{texto}" | {PIPER_BINARY} --model {VOICE_MODEL} --output_file {file}'
    subprocess.run(cmd, shell=True)
    return file

# ANALYSIS
def analisar(audio_path):
    if not audio_path:
        return "No audio.", None

    result = whisper_model.transcribe(audio_path)
    user_text = result["text"].strip()

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

    output = llm(prompt, max_tokens=256)
    raw = output['choices'][0]['text']

    try:
        data = json.loads(raw[raw.find("{"):raw.rfind("}")+1])
    except:
        return raw, falar(raw)

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
            datetime.datetime.now()
        ))
        conn.commit()

        reply += f"\nCorrection: {data['correction']}"

    return f"You: {user_text}\nAI: {reply}", falar(reply)

# UI
with gr.Blocks(title="Echo Tutor") as demo:
    gr.Markdown("# Echo Tutor – Adaptive English")

    inp = gr.Audio(sources=["microphone"], type="filepath")
    out_txt = gr.Textbox()
    out_aud = gr.Audio(autoplay=True)
    gr.Button("Send").click(analisar, inp, [out_txt, out_aud])

if __name__ == "__main__":
    demo.launch(server_name="0.0.0.0", server_port=7860)
