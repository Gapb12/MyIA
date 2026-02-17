#!/bin/bash
set -e

echo "================================================"
echo "🚀 INSTALANDO ECHO TUTOR (TERMUX ANDROID ARM64)"
echo "================================================"

# =========================
# 0. Verificar Termux
# =========================
if [ "$PREFIX" != "/data/data/com.termux/files/usr" ]; then
  echo "❌ Execute dentro do Termux."
  exit 1
fi

# =========================
# 1. Atualizar pacotes
# =========================
echo ">>> [1/6] Atualizando pacotes..."
pkg update -y
pkg install -y \
python \
git \
wget \
tar \
clang \
cmake \
libopenblas \
pkg-config

# =========================
# 2. Criar ambiente virtual
# =========================
echo ">>> [2/6] Criando ambiente virtual..."

if [ -d "venv" ]; then
  rm -rf venv
fi

python -m venv venv
source venv/bin/activate

pip install --upgrade pip wheel setuptools

# =========================
# 3. Instalar dependências Python
# =========================
echo ">>> [3/6] Instalando dependências Python..."

export PIP_NO_BUILD_ISOLATION=1
export PIP_USE_PEP517=0

pkg install -y python-numpy

pip install \
gradio \
soundfile \
thefuzz \
python-Levenshtein \
requests \
ctranslate2==4.3.1 \
tokenizers==0.13.3 --only-binary=:all: \
faster-whisper==1.0.3 \
huggingface-hub

# =========================
# 4. Compilar llama-cpp-python otimizado
# =========================
echo ">>> [4/6] Compilando llama-cpp-python (OpenBLAS + Native)..."

export CMAKE_ARGS="-DGGML_OPENBLAS=on -DGGML_NATIVE=on"
export FORCE_CMAKE=1

pip install llama-cpp-python --force-reinstall --upgrade --no-cache-dir

# =========================
# 5. Baixar modelos
# =========================
echo ">>> [5/6] Baixando modelos..."

mkdir -p models/piper

# Llama 3 8B Q4_K_S
if [ ! -f "models/llama-3-8b.gguf" ]; then
  echo "Baixando Llama 3 8B Q4_K_S..."
  wget https://huggingface.co/bartowski/Meta-Llama-3-8B-Instruct-GGUF/resolve/main/Meta-Llama-3-8B-Instruct-Q4_K_S.gguf \
  -O models/llama-3-8b.gguf
fi

# Piper binário ARM64
if [ ! -f "models/piper/piper" ]; then
  echo "Baixando Piper ARM64..."
  wget https://github.com/rhasspy/piper/releases/download/v1.2.0/piper_linux_aarch64.tar.gz
  tar -xvf piper_linux_aarch64.tar.gz -C models/
  rm piper_linux_aarch64.tar.gz
  mv models/piper_linux_aarch64/* models/piper/
  rmdir models/piper_linux_aarch64
  chmod +x models/piper/piper
fi

# Voz Amy
if [ ! -f "models/piper/en_US-amy-medium.onnx" ]; then
  echo "Baixando voz Amy..."
  wget https://huggingface.co/rhasspy/piper-voices/resolve/main/en/en_US/amy/medium/en_US-amy-medium.onnx \
  -O models/piper/en_US-amy-medium.onnx
  wget https://huggingface.co/rhasspy/piper-voices/resolve/main/en/en_US/amy/medium/en_US-amy-medium.onnx.json \
  -O models/piper/en_US-amy-medium.onnx.json
fi

# =========================
# 6. Criar start.sh
# =========================
echo ">>> [6/6] Criando start.sh..."

cat <<EOF > start.sh
#!/bin/bash
source venv/bin/activate
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
