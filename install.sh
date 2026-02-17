#!/bin/bash
set -e
echo "================================================"
echo "🚀 INSTALANDO ECHO TUTOR (TERMUX ARM64 - FIX ORJSON/MATURIN COM PYTHON 3.11)"
echo "================================================"

# 1. Atualizar repositório
echo ">>> [1/8] Atualizando Termux..."
pkg update -y

# 2. Instalar Python 3.11 + toolchain completa
echo ">>> [2/8] Instalando Python 3.11 e toolchain..."
pkg install -y python-3.11 git wget tar clang make cmake ninja patchelf autoconf automake libtool pkg-config libopenblas ffmpeg python-numpy libsndfile onnxruntime

# 3. Criar ambiente virtual com Python 3.11
echo ">>> [3/8] Criando venv com Python 3.11..."
rm -rf venv311  # Limpa se existir
python3.11 -m venv venv311 --system-site-packages  # Usa numpy do pkg
source venv311/bin/activate
pip install --upgrade pip wheel setuptools

# 4. Instalar dependências Python (downgrades para compatibilidade)
echo ">>> [4/8] Instalando dependências Python..."
export CMAKE_ARGS="-DGGML_OPENBLAS=on -DGGML_NATIVE=on -DGGML_NO_OPENMP=ON"
export FORCE_CMAKE=1
pip install gradio soundfile thefuzz python-Levenshtein requests tokenizers==0.13.3 huggingface-hub
pip install llama-cpp-python --force-reinstall --no-cache-dir
pip install faster-whisper
pip install piper-tts --no-deps  # Evita conflitos onnxruntime
pip install orjson==3.9.15  # Versão com wheels melhores para ARM64

# 5. Baixar modelos (use 3B leve)
echo ">>> [5/8] Baixando modelos..."
mkdir -p models/piper
if [ ! -f "models/llama-3-3b.gguf" ]; then
  wget https://huggingface.co/bartowski/Meta-Llama-3-3B-Instruct-GGUF/resolve/main/Meta-Llama-3-3B-Instruct-Q4_K_M.gguf -O models/llama-3-3b.gguf
fi
if [ ! -f "models/piper/piper" ]; then
  wget https://github.com/rhasspy/piper/releases/download/v1.2.0/piper_linux_aarch64.tar.gz
  tar -xvf piper_linux_aarch64.tar.gz -C models/
  rm piper_linux_aarch64.tar.gz
  mv models/piper_linux_aarch64/* models/piper/
  rmdir models/piper_linux_aarch64
  chmod +x models/piper/piper
fi
if [ ! -f "models/piper/en_US-amy-medium.onnx" ]; then
  wget https://huggingface.co/rhasspy/piper-voices/resolve/main/en/en_US/amy/medium/en_US-amy-medium.onnx -O models/piper/en_US-amy-medium.onnx
  wget https://huggingface.co/rhasspy/piper-voices/resolve/main/en/en_US/amy/medium/en_US-amy-medium.onnx.json -O models/piper/en_US-amy-medium.onnx.json
fi

# 6. Teste imports básicos
echo ">>> [6/8] Testando imports..."
python -c "import faster_whisper; import llama_cpp; import piper_tts; import orjson; print('Imports OK')"

# 7. Criar start.sh ajustado para Python 3.11
echo ">>> [7/8] Criando start.sh..."
cat <<EOF > start.sh
#!/bin/bash
source venv311/bin/activate
python app.py
EOF
chmod +x start.sh

# 8. Opcional: Widget setup (como antes)
echo ">>> [8/8] Configurando widget (opcional)..."
DIR_ATUAL=$(pwd)
cat <<EOF > setup_widget.py
import os
import stat
atalho_dir = os.path.expanduser("~/.shortcuts")
atalho_path = os.path.join(atalho_dir, "EchoTutor")
projeto_dir = "$DIR_ATUAL"
if not os.path.exists(atalho_dir):
    os.makedirs(atalho_dir)
conteudo = f"#!/bin/bash\ncd {projeto_dir} && ./start.sh\n"
with open(atalho_path, "w") as f:
    f.write(conteudo)
st = os.stat(atalho_path)
os.chmod(atalho_path, st.st_mode | stat.S_IEXEC)
print(f"Widget criado em: {atalho_path}")
EOF
python setup_widget.py
rm setup_widget.py

echo ""
echo "================================================"
echo "✅ INSTALAÇÃO CONCLUÍDA!"
echo "Rode ./start.sh para testar"
echo "Acesse http://127.0.0.1:7860 no browser do celular"
echo "================================================"
