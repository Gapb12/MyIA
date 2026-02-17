#!/bin/bash
set -e

echo "================================================"
echo "🚀 INSTALANDO ECHO TUTOR (ANDROID ARM64 - ESTÁVEL)"
echo "================================================"

# =========================
# 0. Verificar Termux
# =========================
if [ "$PREFIX" != "/data/data/com.termux/files/usr" ]; then
  echo "❌ Execute dentro do Termux."
  exit 1
fi

# =========================
# 1. Atualizar pacotes base
# =========================
echo ">>> [1/8] Atualizando Termux..."
pkg update -y
pkg install -y wget git clang cmake libopenblas pkg-config

# =========================
# 2. Instalar Miniforge (se não existir)
# =========================
echo ">>> [2/8] Verificando Miniforge..."

if [ ! -d "$HOME/miniforge3" ]; then
    echo "Instalando Miniforge ARM64..."
    wget https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-Linux-aarch64.sh -O miniforge.sh
    bash miniforge.sh -b -p $HOME/miniforge3
    rm miniforge.sh
fi

source $HOME/miniforge3/bin/activate

# =========================
# 3. Criar ambiente Python 3.11
# =========================
echo ">>> [3/8] Criando ambiente Python 3.11..."

if conda env list | grep -q echo; then
    conda remove -n echo --all -y
fi

conda create -n echo python=3.11 -y
conda activate echo

# =========================
# 4. Atualizar pip
# =========================
echo ">>> [4/8] Atualizando pip..."
pip install --upgrade pip wheel setuptools

# =========================
# 5. Instalar dependências Python
# =========================
echo ">>> [5/8] Instalando dependências..."

pip install \
numpy \
gradio \
soundfile \
thefuzz \
python-Levenshtein \
requests \
tokenizers==0.13.3 \
ctranslate2==4.3.1 \
faster-whisper==1.0.3 \
huggingface-hub

# =========================
# 6. Compilar llama-cpp-python
# =========================
echo ">>> [6/8] Compilando llama-cpp-python (OpenBLAS + Native)..."

export CMAKE_ARGS="-DGGML_OPENBLAS=on -DGGML_NATIVE=on"
export FORCE_CMAKE=1

pip install llama-cpp-python --force-reinstall --upgrade --no-cache-dir

# =========================
# 7. Baixar modelos
# =========================
echo ">>> [7/8] Baixando modelos..."

mkdir -p models/piper

# Llama 3 8B Q4_K_S
if [ ! -f "models/llama-3-8b.gguf" ]; then
    echo "Baixando Llama 3 8B Q4_K_S..."
    wget https://huggingface.co/bartowski/Meta-Llama-3-8B-Instruct-GGUF/resolve/main/Meta-Llama-3-8B-Instruct-Q4_K_S.gguf \
    -O models/llama-3-8b.gguf
fi

# Piper ARM64
if [ ! -f "models/piper/piper" ]; then
    echo "Baixando Piper..."
    wget https://github.com/rhasspy/piper/releases/download/v1.2.0/piper_linux_aarch64.tar.gz
    tar -xvf piper_linux_aarch64.tar.gz -C models/
    rm piper_linux_aarch64.tar.gz
    mv models/piper_linux_aarch64/* models/piper/
    rmdir models/piper_linux_aarch64
    chmod +x models/piper/piper
fi

# Voz Amy
if [ ! -f "models/piper/en_US-amy-medium.onnx" ]; then
    wget https://huggingface.co/rhasspy/piper-voices/resolve/main/en/en_US/amy/medium/en_US-amy-medium.onnx \
    -O models/piper/en_US-amy-medium.onnx
    wget https://huggingface.co/rhasspy/piper-voices/resolve/main/en/en_US/amy/medium/en_US-amy-medium.onnx.json \
    -O models/piper/en_US-amy-medium.onnx.json
fi

# =========================
# 8. Criar start.sh
# =========================
echo ">>> [8/8] Criando start.sh..."

cat <<EOF > start.sh
#!/bin/bash
source \$HOME/miniforge3/bin/activate
conda activate echo
python app.py
EOF

chmod +x start.sh

echo ""
echo "================================================"
echo "✅ INSTALAÇÃO CONCLUÍDA"
echo ""
echo "Para iniciar:"
echo "./start.sh"
echo "================================================"
