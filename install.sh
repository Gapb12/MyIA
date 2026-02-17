#!/bin/bash
set -e

echo "================================================"
echo "🚀 INSTALANDO ECHO TUTOR (ANDROID TERMUX)"
echo "================================================"

# =========================
# 0. Verificar ambiente Termux
# =========================
if [ "$PREFIX" != "/data/data/com.termux/files/usr" ]; then
  echo "❌ Execute este script dentro do Termux."
  exit 1
fi

# =========================
# 1. Atualizar pacotes (SEM upgrade agressivo)
# =========================
echo ">>> [1/8] Atualizando pacotes..."
pkg update -y
pkg install -y python git rust binutils build-essential cmake clang \
libopenblas ffmpeg wget tar ninja pkg-config libjpeg-turbo

# =========================
# 2. Criar ambiente virtual limpo
# =========================
echo ">>> [2/8] Criando ambiente virtual..."
if [ ! -d "venv" ]; then
    python -m venv venv
fi
source venv/bin/activate

pip install --upgrade pip wheel setuptools

# =========================
# 3. Instalar libs Python básicas
# =========================
echo ">>> [3/8] Instalando bibliotecas Python..."
pip install "av>=13.0.0" --no-binary av
pip install gradio soundfile thefuzz[similarity] python-Levenshtein requests
pip install onnxruntime==1.17.0
pip install numpy

# =========================
# 4. Verificar / Compilar CTranslate2
# =========================
echo ">>> [4/8] Verificando CTranslate2..."

if python -c "import ctranslate2" 2>/dev/null; then
    echo "CTranslate2 já instalado."
else
    echo "Compilando CTranslate2 (ARM64)..."
    git clone --recursive https://github.com/OpenNMT/CTranslate2.git
    cd CTranslate2
    git submodule update --init --recursive

    mkdir build && cd build
    cmake .. \
      -DCMAKE_BUILD_TYPE=Release \
      -DOPENMP_RUNTIME=COMP \
      -DWITH_OPENBLAS=ON \
      -DWITH_MKL=OFF \
      -DWITH_RUY=ON \
      -DCMAKE_INSTALL_PREFIX=$PREFIX

    make -j$(nproc)
    make install

    cd ../python
    pip install -v -U .
    cd ../..
fi

# =========================
# 5. Instalar Faster-Whisper
# =========================
echo ">>> [5/8] Instalando Faster-Whisper..."
pip install faster-whisper huggingface-hub tokenizers

# =========================
# 6. Compilar llama-cpp-python otimizado
# =========================
echo ">>> [6/8] Compilando Llama.cpp otimizado..."

export CMAKE_ARGS="-DGGML_OPENBLAS=on -DGGML_NATIVE=on"
export FORCE_CMAKE=1

pip install llama-cpp-python --force-reinstall --upgrade --no-cache-dir

# =========================
# 7. Baixar modelos
# =========================
echo ">>> [7/8] Baixando modelos..."

mkdir -p models/piper

# Llama 3 8B Q4_K_S (menos RAM que Q4_K_M)
if [ ! -f "models/llama-3-8b.gguf" ]; then
    echo "Baixando Llama-3 Q4_K_S..."
    wget https://huggingface.co/bartowski/Meta-Llama-3-8B-Instruct-GGUF/resolve/main/Meta-Llama-3-8B-Instruct-Q4_K_S.gguf \
    -O models/llama-3-8b.gguf
else
    echo "Modelo Llama já existe."
fi

# Piper Engine
if [ ! -f "models/piper/piper" ]; then
    echo "Baixando Piper..."
    wget https://github.com/rhasspy/piper/releases/download/v1.2.0/piper_linux_aarch64.tar.gz
    tar -xvf piper_linux_aarch64.tar.gz -C models/
    rm piper_linux_aarch64.tar.gz

    if [ -d "models/piper_linux_aarch64" ]; then
        mv models/piper_linux_aarch64/* models/piper/
        rmdir models/piper_linux_aarch64
    fi

    chmod +x models/piper/piper
else
    echo "Piper já instalado."
fi

# Voz Amy
if [ ! -f "models/piper/en_US-amy-medium.onnx" ]; then
    echo "Baixando voz Amy..."
    wget https://huggingface.co/rhasspy/piper-voices/resolve/main/en/en_US/amy/medium/en_US-amy-medium.onnx \
    -O models/piper/en_US-amy-medium.onnx

    wget https://huggingface.co/rhasspy/piper-voices/resolve/main/en/en_US/amy/medium/en_US-amy-medium.onnx.json \
    -O models/piper/en_US-amy-medium.onnx.json
else
    echo "Voz já instalada."
fi

# =========================
# 8. Criar start.sh
# =========================
echo ">>> [8/8] Criando start.sh..."

cat <<EOF > start.sh
#!/bin/bash
source venv/bin/activate
python app.py
EOF

chmod +x start.sh

echo ""
echo "================================================"
echo "✅ INSTALAÇÃO CONCLUÍDA"
echo "Para iniciar:"
echo "./start.sh"
echo "================================================"
