import gradio as gr
from faster_whisper import WhisperModel
from llama_cpp import Llama
import sqlite3
import datetime
import json
import time
import re
import gc
from thefuzz import fuzz

# ================= CONFIG =================

MODEL_PATH = "models/llama-3-8b.gguf"
DB_NAME = "echo_tutor.db"

PRON_THRESHOLD_STRICT = -0.55
FUZZ_THRESHOLD = 93
LLM_IDLE_TIMEOUT = 300

llm = None
last_llm_use = time.time()

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
    success_streak INTEGER DEFAULT 0,
    next_review_date DATETIME,
    status TEXT DEFAULT 'ACTIVE'
);
""")

c.execute("""
CREATE TABLE IF NOT EXISTS student_profile (
    id INTEGER PRIMARY KEY CHECK (id=1),
    grammar_errors INTEGER DEFAULT 0,
    vocab_errors INTEGER DEFAULT 0,
    pronunciation_errors INTEGER DEFAULT 0,
    total_sentences INTEGER DEFAULT 0,
    level TEXT DEFAULT 'A2'
);
""")

c.execute("INSERT OR IGNORE INTO student_profile (id) VALUES (1)")
conn.commit()

# ================= MODELS =================

whisper = WhisperModel("base.en", device="cpu", compute_type="int8")

def load_llm():
    global llm, last_llm_use
    if llm is None:
        llm = Llama(model_path=MODEL_PATH, n_ctx=4096, n_gpu_layers=0)
    last_llm_use = time.time()

def check_idle():
    global llm
    if llm and time.time() - last_llm_use > LLM_IDLE_TIMEOUT:
        llm = None
        gc.collect()

# ================= UTIL =================

def normalizar(txt):
    txt = txt.lower()
    txt = re.sub(r'[^\w\s]', '', txt)
    return re.sub(r'\s+', ' ', txt).strip()

def next_review_interval(count):
    intervals = [1,2,4,7,15,30]
    return datetime.datetime.now() + datetime.timedelta(days=intervals[min(count,len(intervals)-1)])

def get_level():
    c.execute("SELECT grammar_errors, vocab_errors, pronunciation_errors, total_sentences FROM student_profile WHERE id=1")
    g,v,p,t = c.fetchone()

    if t < 20:
        return "A2"
    error_rate = (g+v+p)/max(t,1)

    if error_rate > 0.5:
        return "A2"
    elif error_rate > 0.3:
        return "B1"
    elif error_rate > 0.15:
        return "B2"
    else:
        return "C1"

# ================= CORE =================

def analisar(audio_path):
    check_idle()

    segments,_ = whisper.transcribe(audio_path)
    segments=list(segments)
    if not segments:
        return "No speech detected."

    avg_logprob=sum(s.avg_logprob for s in segments)/len(segments)

    if avg_logprob < PRON_THRESHOLD_STRICT:
        c.execute("UPDATE student_profile SET pronunciation_errors=pronunciation_errors+1 WHERE id=1")
        conn.commit()
        return "Pronunciation unclear. Repeat clearly."

    user_text=" ".join(s.text for s in segments).strip()

    load_llm()

    level=get_level()

    system_prompt=f"""
You are a strict English Tutor.
Student level: {level}.
Return ONLY JSON:
{{
 "reply": "string",
 "has_error": true/false,
 "correction": "string",
 "error_type": "grammar|vocab|pronunciation",
 "explanation": "short didactic explanation with example"
}}
Be pedagogical and precise.
"""

    prompt=f"{system_prompt}\nUser: {user_text}\nAssistant:"

    out=llm(prompt, max_tokens=300, temperature=0.1)
    raw=out["choices"][0]["text"]

    data=json.loads(raw[raw.find("{"):raw.rfind("}")+1])

    c.execute("UPDATE student_profile SET total_sentences=total_sentences+1 WHERE id=1")

    reply=data["reply"]

    if data["has_error"]:
        correction=data["correction"]
        error_type=data["error_type"]

        if error_type=="grammar":
            c.execute("UPDATE student_profile SET grammar_errors=grammar_errors+1 WHERE id=1")
        elif error_type=="vocab":
            c.execute("UPDATE student_profile SET vocab_errors=vocab_errors+1 WHERE id=1")

        c.execute("""
        INSERT INTO learning_logs
        (user_input, corrected_version, error_type, explanation, next_review_date)
        VALUES (?,?,?,?,?)
        """,(user_text,correction,error_type,data["explanation"],next_review_interval(0)))

        reply += f"\nCorrection: {correction}"

    conn.commit()
    return f"You: {user_text}\nTutor: {reply}"

# ================= REVIEW =================

def revisar():
    c.execute("""
    SELECT id,user_input,corrected_version,success_streak
    FROM learning_logs
    WHERE next_review_date<=datetime('now')
    AND status='ACTIVE'
    ORDER BY next_review_date ASC
    LIMIT 1
    """)
    return c.fetchone()

def validar(audio_path,id_log):
    segments,_=whisper.transcribe(audio_path)
    tentativa=" ".join(s.text for s in segments).strip()

    c.execute("SELECT corrected_version,review_count,success_streak FROM learning_logs WHERE id=?",(id_log,))
    correto,count,streak=c.fetchone()

    ratio=fuzz.token_sort_ratio(normalizar(tentativa),normalizar(correto))

    if ratio>FUZZ_THRESHOLD:
        streak+=1
        count+=1
        if streak>=3:
            c.execute("UPDATE learning_logs SET status='MASTERED' WHERE id=?",(id_log,))
            conn.commit()
            return "Mastered."

        c.execute("""
        UPDATE learning_logs
        SET review_count=?,success_streak=?,next_review_date=?
        WHERE id=?
        """,(count,streak,next_review_interval(count),id_log))

        conn.commit()
        return f"Correct ({ratio}%)"

    else:
        c.execute("""
        UPDATE learning_logs
        SET success_streak=0,next_review_date=?
        WHERE id=?
        """,(next_review_interval(0),id_log))
        conn.commit()
        return f"Incorrect ({ratio}%) Repeat again."

# ================= UI =================

with gr.Blocks() as demo:
    gr.Markdown("# Echo Tutor – Extreme Mode")

    audio=gr.Audio(sources=["microphone"],type="filepath")
    out=gr.Textbox()
    gr.Button("Analyze").click(analisar,audio,out)

demo.launch(server_name="0.0.0.0",server_port=7860)
