import gradio as gr
from faster_whisper import WhisperModel
from llama_cpp import Llama
import subprocess
import json
import sqlite3
import datetime
import os
import re

# CONFIGURAÇÃO
MODEL_PATH = "models/llama-3-8b.gguf"
PIPER_BINARY = "./models/piper/piper"
VOICE_MODEL = "models/piper/en_US-amy-medium.onnx"
DB_NAME = "echo_tutor.db"

# BANCO DE DADOS
conn = sqlite3.connect(DB_NAME, check_same_thread=False)
c = conn.cursor()
c.execute('''CREATE TABLE IF NOT EXISTS logs 
             (id INTEGER PRIMARY KEY, user_text TEXT, correction TEXT, 
              explanation TEXT, error_type TEXT, timestamp DATETIME)''')
conn.commit()

# CARREGAR MODELOS
print(">>> Carregando Whisper...")
whisper = WhisperModel("tiny.en", device="cpu", compute_type="int8")

print(">>> Carregando Llama-3...")
llm = Llama(model_path=MODEL_PATH, n_ctx=2048, n_gpu_layers=-1, verbose=False)

def falar_piper(texto):
    output_file = "resposta.wav"
    texto_limpo = re.sub(r'[^a-zA-Z0-9 .,?!]', '', texto)
    cmd = f'echo "{texto_limpo}" | {PIPER_BINARY} --model {VOICE_MODEL} --output_file {output_file}'
    subprocess.run(cmd, shell=True)
    return output_file

def analisar(audio):
    if not audio: return "Sem áudio.", None

    # 1. Transcrever
    segments, _ = whisper.transcribe(audio, beam_size=5)
    user_text = " ".join([s.text for s in segments]).strip()
    if len(user_text) < 2: return "Não entendi.", None

    # 2. Analisar com IA
    prompt = f"""<|begin_of_text|><|start_header_id|>system<|end_header_id|>
You are a strict English Tutor. Analyze the user sentence.
Output JSON ONLY: {{"reply": "response", "has_error": true/false, "correction": "fix", "explanation": "reason", "error_type": "grammar"}}
<|eot_id|><|start_header_id|>user<|end_header_id|>
{user_text}<|eot_id|><|start_header_id|>assistant<|end_header_id|>"""

    output = llm(prompt, max_tokens=256, stop=["<|eot_id|>"], echo=False)
    raw = output['choices'][0]['text']

    try:
        json_str = raw[raw.find('{'):raw.rfind('}')+1]
        data = json.loads(json_str)
        reply = data['reply']
        if data['has_error']:
            reply += f"\n\nCorrection: {data['correction']} ({data['explanation']})"
            c.execute("INSERT INTO logs (user_text, correction, explanation, error_type, timestamp) VALUES (?,?,?,?,?)", 
                      (user_text, data['correction'], data['explanation'], data['error_type'], datetime.datetime.now()))
            conn.commit()
    except:
        reply = "I heard you, but I couldn't check the grammar perfectly. Let's continue."

    # 3. Falar
    audio_resp = falar_piper(reply)
    return f"You: {user_text}\nAI: {reply}", audio_resp

with gr.Blocks(title="Echo Tutor") as demo:
    gr.Markdown("# 🇧🇷 Echo Tutor S23")
    with gr.Row():
        inp = gr.Audio(sources=["microphone"], type="filepath", label="Fale")
        out = gr.Audio(autoplay=True, label="Professor")
    txt = gr.Textbox(label="Correção")
    inp.change(analisar, inp, [txt, out])

demo.launch(server_name="0.0.0.0", server_port=7860)
