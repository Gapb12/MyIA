#!/bin/bash
set -e

echo "================================================"
echo "🚀 INSTALANDO ECHO TUTOR (TERMUX ARM64 ESTÁVEL)"
echo "================================================"

# =========================
# 0. Verificar Termux
# =========================
if [ "$PREFIX" != "/data/data/com.termux/files/usr" ]; then
  echo "❌ Execute dentro do Termux."
  exit 1
fi

# =========================
# 1. Atualizar sistema
# =========================
echo ">>> [1/7] Atualizando Termux..."
pkg update -y
pkg upgrade -y

# =========================
# 2. Instalar dependências nativas
# =========================
echo ">>> [2/7] Instalando dependências base..."

pkg install -y \
python \
git \
wget \
ffmpeg \
clang \
cmake \
libopenblas \
pkg-config

# =========================
# 3. Criar ambiente virtual
# =========================
echo ">>> [3/7] Criando ambiente virtual..."

if [ -d "venv" ]; then
  rm -rf venv
fi

python -m venv venv
source venv/bin/activate

pip install --upgrade pip setuptools wheel

# =========================
# 4. Instalar dependências Python
# =========================
echo ">>> [4/7] Instalando dependências Python..."

pip install \
numpy \
gradio \
soundfile \
thefuzz \
python-Levenshtein \
requests \
huggingface-hub \
openai-whisper

# =========================
# 5. Compilar llama-cpp-python
# =========================
echo ">>> [5/7] Compilando llama-cpp-python (OpenBLAS + Native)..."

export CMAKE_ARGS="-DGGML_OPENBLAS=on -DGGML_NATIVE=on"
export FORCE_CMAKE=1

pip install llama-cpp-python --no-cache-dir

# =========================
# 6. Baixar modelos
# =========================
echo ">>> [6/7] Baixando modelos..."

mkdir -p models/piper

# Llama 3 8B Q4_K_S
if [ ! -f "models/llama-3-8b.gguf" ]; then
  echo "Baixando Llama 3 8B..."
  wget https://huggingface.co/bartowski/Meta-Llama-3-8B-Instruct-GGUF/resolve/main/Meta-Llama-3-8B-Instruct-Q4_K_S.gguf \
  -O models/llama-3-8b.gguf
fi

# Piper
if [ ! -f "models/piper/piper" ]; then
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
cd \$(dirname "\$0")
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
