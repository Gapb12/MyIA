import gradio as gr
from faster_whisper import WhisperModel
from llama_cpp import Llama
import subprocess
import json
import sqlite3
import datetime
import os
import re
from thefuzz import fuzz  # Para comparar a repetição do usuário

# --- CONFIGURAÇÃO ---
MODEL_PATH = "models/llama-3-8b.gguf"
PIPER_BINARY = "./models/piper/piper"
VOICE_MODEL = "models/piper/en_US-amy-medium.onnx"
DB_NAME = "echo_tutor.db"

# --- BANCO DE DADOS (SCHEMA COMPLETO) ---
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

# --- CARREGAR MODELOS ---
print(">>> [1/2] Carregando Whisper (Ouvido)...")
whisper = WhisperModel("tiny.en", device="cpu", compute_type="int8")

print(">>> [2/2] Carregando Llama-3 (Cérebro)...")
llm = Llama(model_path=MODEL_PATH, n_ctx=2048, n_gpu_layers=-1, verbose=False)

# --- FUNÇÕES AUXILIARES ---

def falar_piper(texto):
    """Gera áudio e retorna o caminho do arquivo."""
    output_file = f"temp_audio_{int(datetime.datetime.now().timestamp())}.wav"
    texto_limpo = re.sub(r'[^a-zA-Z0-9 .,?!]', '', texto)
    if not os.path.exists(PIPER_BINARY): return None
    cmd = f'echo "{texto_limpo}" | {PIPER_BINARY} --model {VOICE_MODEL} --output_file {output_file}'
    subprocess.run(cmd, shell=True)
    return output_file

def calcular_proxima_revisao(review_count):
    """Algoritmo SRS Simplificado (Ex: 1 dia, 3 dias, 7 dias)"""
    intervals = [1, 3, 7, 14, 30]
    days = intervals[min(review_count, len(intervals)-1)]
    return datetime.datetime.now() + datetime.timedelta(days=days)

# --- CORE LOGIC: CONVERSAÇÃO ---

def analisar_conversa(audio_path):
    if not audio_path: return "Sem áudio.", None

    # 1. Transcrever com Validação de Confiança (CAMADA A)
    segments, _ = whisper.transcribe(audio_path, beam_size=5)
    full_text = []
    
    for segment in segments:
        # Se a confiança for muito baixa (< -0.6 logprob), rejeita
        if segment.avg_logprob < -0.7: 
            return f"⚠️ I heard something like '{segment.text}', but your pronunciation was unclear. Please try again.", falar_piper("Please pronounce that more clearly.")
        full_text.append(segment.text)
    
    user_text = " ".join(full_text).strip()
    if len(user_text) < 2: return "Audio too short.", None

    # 2. LLM Analysis (CAMADA B)
    system_prompt = """You are a strict English Tutor. Analyze the user sentence.
    Output JSON ONLY: {"reply": "conversational response", "has_error": true/false, "correction": "corrected sentence", "explanation": "grammar rule", "error_type": "grammar/pronunciation"}"""
    
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
            
            # Salvar no DB com SRS inicial
            next_date = datetime.datetime.now() # Revisar agora/logo
            c.execute("""INSERT INTO learning_logs 
                         (user_input, corrected_version, error_type, explanation, next_review_date) 
                         VALUES (?, ?, ?, ?, ?)""",
                      (user_text, correction, data['error_type'], explanation, next_date))
            conn.commit()
            
    except Exception as e:
        print(f"JSON Error: {e}")
        reply = raw # Fallback

    return f"You: {user_text}\nAI: {reply}", falar_piper(reply)

# --- CORE LOGIC: DRILL MODE (REVISÃO) ---

def carregar_exercicio():
    """Busca um erro pendente de revisão"""
    # Pega erros onde a data de revisão é hoje ou no passado
    c.execute("SELECT id, user_input, corrected_version, explanation FROM learning_logs WHERE next_review_date <= datetime('now') ORDER BY next_review_date ASC LIMIT 1")
    row = c.fetchone()
    
    if not row:
        return "No pending reviews! Great job! 🎉", None, None
    
    id_log, original, correcao, explicacao = row
    texto_instrucao = f"📝 Review Time!\nYou said: '{original}'\nCorrect: '{correcao}'\nTip: {explicacao}\n\n👉 Press Record and repeat the CORRECT sentence."
    audio_instrucao = falar_piper(f"Please repeat: {correcao}")
    
    # Retorna ID escondido para validação posterior
    return texto_instrucao, audio_instrucao, id_log

def validar_exercicio(audio_path, id_log):
    if not audio_path or not id_log: return "Record your voice first.", None

    # Transcrever a tentativa do aluno
    segments, _ = whisper.transcribe(audio_path)
    tentativa = " ".join([s.text for s in segments]).strip()
    
    # Buscar a resposta correta no DB
    c.execute("SELECT corrected_version, review_count FROM learning_logs WHERE id = ?", (id_log,))
    row = c.fetchone()
    if not row: return "Error fetching data.", None
    
    correto, review_count = row
    
    # Fuzzy Matching (Comparação flexível)
    ratio = fuzz.ratio(tentativa.lower(), correto.lower())
    
    if ratio > 85: # 85% de similaridade aceitável
        novo_count = review_count + 1
        proxima_data = calcular_proxima_revisao(novo_count)
        c.execute("UPDATE learning_logs SET review_count = ?, next_review_date = ? WHERE id = ?", (novo_count, proxima_data, id_log))
        conn.commit()
        msg = f"✅ Excellent! (Accuracy: {ratio}%)\nMatched: {tentativa}"
        audio = falar_piper("Perfect! Next one.")
    else:
        msg = f"❌ Try again. (Accuracy: {ratio}%)\nYou said: {tentativa}\nTarget: {correto}"
        audio = falar_piper("Not quite. Listen and try again.")
        
    return msg, audio

# --- INTERFACE GRADIO (ABAS) ---

with gr.Blocks(title="Echo Tutor Pro", theme=gr.themes.Soft()) as demo:
    gr.Markdown("# 🦉 Echo Tutor Pro (S23 Ultra)")
    
    with gr.Tabs():
        # ABA 1: CONVERSA LIVRE
        with gr.TabItem("💬 Free Conversation"):
            with gr.Row():
                inp_chat = gr.Audio(sources=["microphone"], type="filepath", label="Fale Livremente")
                out_chat_audio = gr.Audio(label="Professor", autoplay=True)
            out_chat_text = gr.Textbox(label="Transcript & Feedback")
            btn_chat = gr.Button("Send")
            btn_chat.click(analisar_conversa, inp_chat, [out_chat_text, out_chat_audio])
            
        # ABA 2: DRILL MODE (Revisão)
        with gr.TabItem("🏋️ Drill / Review Errors"):
            gr.Markdown("Repita as frases corrigidas para treinar sua memória muscular.")
            with gr.Row():
                btn_load = gr.Button("Load Next Error", variant="primary")
                id_hidden = gr.Number(visible=False) # Para guardar o ID do erro atual
            
            lbl_instruction = gr.Textbox(label="Instruction", value="Click 'Load Next Error' to start.")
            audio_instruction = gr.Audio(label="Listen Correct Version", interactive=False, autoplay=True)
            
            with gr.Row():
                inp_drill = gr.Audio(sources=["microphone"], type="filepath", label="Repeat Here")
                out_drill_audio = gr.Audio(label="Feedback Audio", autoplay=True)
            
            lbl_feedback = gr.Textbox(label="Result")
            btn_check = gr.Button("Check Pronunciation")
            
            # Eventos Drill
            btn_load.click(carregar_exercicio, None, [lbl_instruction, audio_instruction, id_hidden])
            btn_check.click(validar_exercicio, [inp_drill, id_hidden], [lbl_feedback, out_drill_audio])

if __name__ == "__main__":
    demo.launch(server_name="0.0.0.0", server_port=7860)
