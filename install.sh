#!/bin/bash
set -e

echo "================================================"
echo "🚀 INSTALANDO ECHO TUTOR (ANDROID TERMUX ESTÁVEL)"
echo "================================================"

# =========================
# 0. Verificar Termux
# =========================
if [ "$PREFIX" != "/data/data/com.termux/files/usr" ]; then
  echo "❌ Execute dentro do Termux."
  exit 1
fi

# =========================
# 1. Atualizar pacotes (sem upgrade agressivo)
# =========================
echo ">>> [1/7] Atualizando pacotes..."
pkg update -y
pkg install -y python git ffmpeg wget tar clang cmake \
libopenblas build-essential pkg-config libjpeg-turbo

# =========================
# 2. Criar ambiente virtual
# =========================
echo ">>> [2/7] Criando venv..."
if [ ! -d "venv" ]; then
    python -m venv venv
fi
source venv/bin/activate

pip install --upgrade pip wheel setuptools

# =========================
# 3. Instalar libs base
# =========================
echo ">>> [3/7] Instalando libs base..."
pip install numpy
pip install "av>=13.0.0" --no-binary av
pip install gradio soundfile thefuzz[similarity] python-Levenshtein requests
pip install onnxruntime==1.17.0

# =========================
# 4. Instalar STT stack estável (SEM build manual)
# =========================
echo ">>> [4/7] Instalando Faster-Whisper stack estável..."

pip install ctranslate2==4.3.1
pip install tokenizers==0.13.3 --only-binary=:all:
pip install faster-whisper==1.0.3
pip install huggingface-hub

# =========================
# 5. Compilar llama-cpp-python otimizado
# =========================
echo ">>> [5/7] Compilando llama-cpp-python..."

export CMAKE_ARGS="-DGGML_OPENBLAS=on -DGGML_NATIVE=on"
export FORCE_CMAKE=1

pip install llama-cpp-python --force-reinstall --upgrade --no-cache-dir

# =========================
# 6. Baixar modelos
# =========================
echo ">>> [6/7] Baixando modelos..."

mkdir -p models/piper

# Llama 3 8B Q4_K_S (mais leve)
if [ ! -f "models/llama-3-8b.gguf" ]; then
    echo "Baixando Llama-3 Q4_K_S..."
    wget https://huggingface.co/bartowski/Meta-Llama-3-8B-Instruct-GGUF/resolve/main/Meta-Llama-3-8B-Instruct-Q4_K_S.gguf \
    -O models/llama-3-8b.gguf
fi

# Piper
if [ ! -f "models/piper/piper" ]; then
    echo "Baixando Piper..."
    wget https://github.com/rhasspy/piper/releases/download/v1.2.0/piper_linux_aarch64.tar.gz
    tar -xvf piper_linux_aarch64.tar.gz -C models/
    rm piper_linux_aarch64.tar.gz
    mv models/piper_linux_aarch64/* models/piper/
    rmdir models/piper_linux_aarch64
    chmod +x models/piper/piper
fi

# Voz
if [ ! -f "models/piper/en_US-amy-medium.onnx" ]; then
    wget https://huggingface.co/rhasspy/piper-voices/resolve/main/en/en_US/amy/medium/en_US-amy-medium.onnx \
    -O models/piper/en_US-amy-medium.onnx
    wget https://huggingface.co/rhasspy/piper-voices/resolve/main/en/en_US/amy/medium/en_US-amy-medium.onnx.json \
    -O models/piper/en_US-amy-medium.onnx.json
fi

# =========================
# 7. Criar start.sh
# =========================
echo ">>> [7/7] Criando start.sh..."

cat <<EOF > start.sh
#!/bin/bash
source venv/bin/activate
python app.py
EOF

chmod +x start.sh

echo ""
echo "================================================"
echo "✅ INSTALAÇÃO CONCLUÍDA"
echo "Execute:"
echo "./start.sh"
echo "================================================"
