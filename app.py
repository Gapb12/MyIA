import gradio as gr
from faster_whisper import WhisperModel
from llama_cpp import Llama
import subprocess
import json
import sqlite3
import datetime
import os
import re

# --- CONFIGURAÇÃO ---
# Caminhos relativos (baseados na estrutura do seu install.sh)
MODEL_PATH = "models/llama-3-8b.gguf"
PIPER_BINARY = "./models/piper/piper"
VOICE_MODEL = "models/piper/en_US-amy-medium.onnx"
DB_NAME = "echo_tutor.db"

# --- BANCO DE DADOS (MEMÓRIA) ---
conn = sqlite3.connect(DB_NAME, check_same_thread=False)
c = conn.cursor()
# Cria a tabela de logs se não existir
c.execute('''CREATE TABLE IF NOT EXISTS logs 
             (id INTEGER PRIMARY KEY, 
              user_text TEXT, 
              correction TEXT, 
              explanation TEXT, 
              error_type TEXT, 
              timestamp DATETIME)''')
conn.commit()

# --- CARREGAMENTO DOS MODELOS ---
print(">>> [1/2] Carregando Whisper (Ouvido)...")
# 'tiny.en' é ultra rápido no S23. Se quiser mais precisão, mude para 'base.en'
whisper = WhisperModel("tiny.en", device="cpu", compute_type="int8")

print(">>> [2/2] Carregando Llama-3 (Cérebro)...")
# n_gpu_layers=-1 tenta usar toda a aceleração disponível no Termux
llm = Llama(
    model_path=MODEL_PATH,
    n_ctx=2048,      # Tamanho do contexto (memória de curto prazo)
    n_gpu_layers=-1, 
    verbose=False    # Deixe True se quiser ver detalhes técnicos no terminal
)

# --- FUNÇÕES DO SISTEMA ---

def falar_piper(texto):
    """
    Gera áudio offline usando o Piper.
    Recebe texto, limpa caracteres estranhos e cria um arquivo WAV.
    """
    output_file = "resposta_ia.wav"
    
    # Limpeza de segurança para o terminal (evita injeção de comandos)
    texto_limpo = re.sub(r'[^a-zA-Z0-9 .,?!]', '', texto)
    
    if not os.path.exists(PIPER_BINARY):
        return None # Retorna nada se o Piper não estiver instalado

    # Comando que roda o binário do Piper
    cmd = f'echo "{texto_limpo}" | {PIPER_BINARY} --model {VOICE_MODEL} --output_file {output_file}'
    subprocess.run(cmd, shell=True)
    
    return output_file

def analisar_texto(texto_usuario):
    """
    O Cérebro: Envia o texto para o Llama-3 com instruções estritas de professor.
    """
    print(f"Usuário disse: {texto_usuario}")
    
    # O Prompt do Sistema (A "Personalidade" da IA)
    system_prompt = """You are a strict English Tutor.
1. Analyze the user's sentence strictly for grammar, vocabulary, and pronunciation errors.
2. Output ONLY a JSON object with this structure (no extra text):
{
  "reply": "A natural conversational response asking a follow-up question",
  "has_error": true,
  "correction": "The corrected sentence (if error) or null",
  "explanation": "Brief grammar explanation (if error) or null",
  "error_type": "Grammar/Vocab/Pronunciation/None"
}"""

    # Formatação do prompt para o Llama-3
    prompt = f"<|begin_of_text|><|start_header_id|>system<|end_header_id|>\n\n{system_prompt}<|eot_id|><|start_header_id|>user<|end_header_id|>\n\n{texto_usuario}<|eot_id|><|start_header_id|>assistant<|end_header_id|>\n\n"
    
    # Gera a resposta
    output = llm(prompt, max_tokens=512, stop=["<|eot_id|>"], echo=False)
    raw_response = output['choices'][0]['text']
    
    # Tenta extrair e ler o JSON da resposta
    try:
        # Busca o JSON dentro do texto (caso a IA fale algo antes/depois)
        start = raw_response.find('{')
        end = raw_response.rfind('}') + 1
        if start == -1 or end == 0:
            # Fallback se a IA não obedecer o JSON
            return raw_response, False 
            
        json_str = raw_response[start:end]
        data = json.loads(json_str)
        
        resposta_final = data['reply']
        
        # Se houver erro, salva no banco e adiciona explicação
        if data.get('has_error'):
            correction_msg = f"\n[Correction: {data['correction']} - {data['explanation']}]"
            resposta_final += correction_msg
            
            # Salvar no SQLite
            c.execute("INSERT INTO logs (user_text, correction, explanation, error_type, timestamp) VALUES (?, ?, ?, ?, ?)",
                      (texto_usuario, data['correction'], data['explanation'], data['error_type'], datetime.datetime.now()))
            conn.commit()
            print(f"!!! ERRO REGISTRADO: {data['error_type']} !!!")
            
        return resposta_final
        
    except Exception as e:
        print(f"Erro ao processar JSON da IA: {e}")
        return "I understood you, but I had a technical glitch analyzing your grammar. Let's continue.", None

def processar_conversa(audio_path):
    """
    O Fluxo Principal: Áudio -> Texto -> IA -> Áudio
    """
    if not audio_path:
        return "No audio detected.", None
        
    # 1. Transcrever (Speech-to-Text)
    # beam_size=5 melhora a precisão
    segments, _ = whisper.transcribe(audio_path, beam_size=5)
    texto_usuario = " ".join([s.text for s in segments]).strip()
    
    if len(texto_usuario) < 2:
        return "Audio too short or unclear.", None
        
    # 2. Analisar (Brain)
    resposta_texto = analisar_texto(texto_usuario)
    
    # 3. Falar (Text-to-Speech)
    caminho_audio_resposta = falar_piper(resposta_texto)
    
    return f"🗣️ You: {texto_usuario}\n\n🤖 AI: {resposta_texto}", caminho_audio_resposta

# --- INTERFACE GRADIO (FRONTEND) ---
css_custom = """
footer {visibility: hidden}
.gradio-container {background-color: #1e1e1e; color: white}
"""

with gr.Blocks(title="Echo Tutor Local", css=css_custom, theme=gr.themes.Soft()) as demo:
    gr.Markdown("# 🦉 Echo Tutor (S23 Ultra Edition)")
    gr.Markdown("Fale em inglês. Eu vou corrigir sua gramática e salvar seus erros.")
    
    with gr.Row():
        with gr.Column():
            input_audio = gr.Audio(sources=["microphone"], type="filepath", label="Seu Microfone")
            btn_enviar = gr.Button("Enviar / Conversar", variant="primary")
        
        with gr.Column():
            output_audio = gr.Audio(label="Resposta do Professor", autoplay=True, interactive=False)
    
    with gr.Row():
        chat_log = gr.Textbox(label="Log da Conversa (Texto)", lines=5)
    
    # Ação do botão
    btn_enviar.click(fn=processar_conversa, inputs=input_audio, outputs=[chat_log, output_audio])

# Inicia o servidor local
if __name__ == "__main__":
    print(">>> Servidor Iniciado! Acesse: http://localhost:7860")
    demo.launch(server_name="0.0.0.0", server_port=7860, quiet=True)
