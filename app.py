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

# --- CONFIGURAÇÃO ---
MODEL_PATH = "models/llama-3-8b.gguf"
PIPER_BINARY = "./models/piper/piper"
VOICE_MODEL = "models/piper/en_US-amy-medium.onnx"
DB_NAME = "echo_tutor.db"
LOG_FILE = "error_log.txt"  # Arquivo local de erros

# --- BANCO DE DADOS ---
conn = sqlite3.connect(DB_NAME, check_same_thread=False)
c = conn.cursor()
c.execute('''CREATE TABLE IF NOT EXISTS learning_logs 
             (id INTEGER PRIMARY KEY AUTOINCREMENT,
              timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
              user_input TEXT,
              corrected_version TEXT,
              error_type TEXT,
              explanation TEXT,
              review_count INTEGER DEFAULT 0,
              next_review_date DATETIME,
              status TEXT DEFAULT 'ACTIVE')''')
conn.commit()

# --- FUNÇÃO DE LOG LOCAL (SEGURA) ---
def registrar_erro_local(erro_msg, detalhe_tecnico):
    """Salva o erro num arquivo de texto no próprio celular"""
    timestamp = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    log_entry = f"\n{'='*30}\nDATA: {timestamp}\nERRO: {erro_msg}\nDETALHES:\n{detalhe_tecnico}\n{'='*30}\n"
    
    try:
        with open(LOG_FILE, "a", encoding="utf-8") as f:
            f.write(log_entry)
        print(f"❌ Erro registrado em {LOG_FILE}")
    except Exception as e:
        print(f"Falha ao salvar log: {e}")

# --- CARREGAR MODELOS ---
print(">>> [1/2] Carregando Whisper...")
whisper = WhisperModel("tiny.en", device="cpu", compute_type="int8")

print(">>> [2/2] Carregando Llama-3...")
llm = Llama(model_path=MODEL_PATH, n_ctx=2048, n_gpu_layers=-1, verbose=False)

# --- FUNÇÕES AUXILIARES ---
def falar_piper(texto):
    output_file = f"temp_audio_{int(datetime.datetime.now().timestamp())}.wav"
    texto_limpo = re.sub(r'[^a-zA-Z0-9 .,?!]', '', texto)
    if not os.path.exists(PIPER_BINARY): return None
    cmd = f'echo "{texto_limpo}" | {PIPER_BINARY} --model {VOICE_MODEL} --output_file {output_file}'
    subprocess.run(cmd, shell=True)
    return output_file

def calcular_proxima_revisao(review_count):
    intervals = [1, 3, 7, 14, 30]
    days = intervals[min(review_count, len(intervals)-1)]
    return datetime.datetime.now() + datetime.timedelta(days=days)

# --- CORE LOGIC ---
def analisar_conversa(audio_path):
    try:
        if not audio_path: return "Sem áudio.", None

        segments, _ = whisper.transcribe(audio_path, beam_size=5)
        full_text = []
        for segment in segments:
            if segment.avg_logprob < -0.7: 
                return "⚠️ Pronúncia pouco clara. Tente novamente.", falar_piper("Please speak clearly.")
            full_text.append(segment.text)
        
        user_text = " ".join(full_text).strip()
        if len(user_text) < 2: return "Áudio muito curto.", None

        system_prompt = """You are a strict English Tutor. Analyze the user sentence.
        Output JSON ONLY: {"reply": "response", "has_error": true/false, "correction": "fix", "explanation": "reason", "error_type": "grammar"}"""
        
        prompt = f"<|begin_of_text|><|start_header_id|>system<|end_header_id|>\n{system_prompt}\n<|eot_id|><|start_header_id|>user<|end_header_id|>\n{user_text}\n<|eot_id|><|start_header_id|>assistant<|end_header_id|>\n"
        
        output = llm(prompt, max_tokens=256, stop=["<|eot_id|>"], echo=False)
        raw = output['choices'][0]['text']

        try:
            json_str = raw[raw.find('{'):raw.rfind('}')+1]
            data = json.loads(json_str)
            reply = data['reply']
            if data.get('has_error'):
                correction = data['correction']
                explanation = data['explanation']
                reply += f"\n\n🛑 Correction: {correction}"
                c.execute("INSERT INTO learning_logs (user_input, corrected_version, error_type, explanation, next_review_date) VALUES (?, ?, ?, ?, ?)",
                          (user_text, correction, data['error_type'], explanation, datetime.datetime.now()))
                conn.commit()
        except Exception as e:
            print(f"JSON Parse Error: {e}") # Erro leve, não trava o app
            reply = raw

        return f"You: {user_text}\nAI: {reply}", falar_piper(reply)

    except Exception as e:
        # CAPTURA O ERRO E SALVA NO ARQUIVO LOCAL
        err_msg = str(e)
        stack_trace = traceback.format_exc()
        print(f"ERRO CRÍTICO: {err_msg}")
        registrar_erro_local(err_msg, stack_trace)
        return f"Ocorreu um erro. Verifique o arquivo error_log.txt", None

def carregar_exercicio():
    try:
        c.execute("SELECT id, user_input, corrected_version, explanation FROM learning_logs WHERE next_review_date <= datetime('now') ORDER BY next_review_date ASC LIMIT 1")
        row = c.fetchone()
        if not row: return "No pending reviews! 🎉", None, None
        
        id_log, original, correcao, explicacao = row
        return f"📝 Review:\nSaid: '{original}'\nCorrect: '{correcao}'\nTip: {explicacao}", falar_piper(f"Repeat: {correcao}"), id_log
    except Exception as e:
        registrar_erro_local(str(e), traceback.format_exc())
        return "Erro ao carregar exercício.", None, None

def validar_exercicio(audio_path, id_log):
    try:
        if not audio_path or not id_log: return "Grave sua voz primeiro.", None
        segments, _ = whisper.transcribe(audio_path)
        tentativa = " ".join([s.text for s in segments]).strip()
        
        c.execute("SELECT corrected_version, review_count FROM learning_logs WHERE id = ?", (id_log,))
        row = c.fetchone()
        if not row: return "Erro de dados.", None
        
        correto, review_count = row
        ratio = fuzz.ratio(tentativa.lower(), correto.lower())
        
        if ratio > 85:
            novo_count = review_count + 1
            proxima = calcular_proxima_revisao(novo_count)
            c.execute("UPDATE learning_logs SET review_count = ?, next_review_date = ? WHERE id = ?", (novo_count, proxima, id_log))
            conn.commit()
            return f"✅ Excellent! ({ratio}%)\nMatched: {tentativa}", falar_piper("Perfect!")
        else:
            return f"❌ Try again. ({ratio}%)\nSaid: {tentativa}", falar_piper("Try again.")
            
    except Exception as e:
        registrar_erro_local(str(e), traceback.format_exc())
        return "Erro na validação.", None

# --- INTERFACE ---
with gr.Blocks(title="Echo Tutor Pro", theme=gr.themes.Soft()) as demo:
    gr.Markdown("# 🦉 Echo Tutor Pro")
    with gr.Tabs():
        with gr.TabItem("💬 Conversation"):
            inp = gr.Audio(sources=["microphone"], type="filepath")
            out_txt = gr.Textbox()
            out_aud = gr.Audio(autoplay=True)
            gr.Button("Send").click(analisar_conversa, inp, [out_txt, out_aud])
            
        with gr.TabItem("🏋️ Review"):
            btn_load = gr.Button("Load Next")
            id_h = gr.Number(visible=False)
            lbl = gr.Textbox()
            aud_ref = gr.Audio(interactive=False, autoplay=True)
            inp_drill = gr.Audio(sources=["microphone"], type="filepath")
            res_txt = gr.Textbox()
            res_aud = gr.Audio(autoplay=True)
            btn_check = gr.Button("Check")
            
            btn_load.click(carregar_exercicio, None, [lbl, aud_ref, id_h])
            btn_check.click(validar_exercicio, [inp_drill, id_h], [res_txt, res_aud])

if __name__ == "__main__":
    demo.launch(server_name="0.0.0.0", server_port=7860)
