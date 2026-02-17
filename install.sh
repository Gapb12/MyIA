#!/bin/bash
set -e

echo "================================================"
echo "🚀 INSTALANDO ECHO TUTOR (TERMUX ARM64 COMPLETO)"
echo "================================================"

# =========================
# 0. Verificar Termux
# =========================
if [ "$PREFIX" != "/data/data/com.termux/files/usr" ]; then
  echo "❌ Execute dentro do Termux."
  exit 1
fi

# =========================
# 1. Atualizar repositório
# =========================
echo ">>> [1/7] Atualizando Termux..."
pkg update -y

# =========================
# 2. Instalar toolchain COMPLETA
# =========================
echo ">>> [2/7] Instalando toolchain completa..."

pkg install -y \
python \
git \
wget \
tar \
clang \
make \
cmake \
ninja \
patchelf \
autoconf \
automake \
libtool \
pkg-config \
libopenblas \
ffmpeg

# =========================
# 3. Criar ambiente virtual
# =========================
echo ">>> [3/7] Criando ambiente virtual..."

if [ -d "venv" ]; then
  rm -rf venv
fi

python -m venv venv
source venv/bin/activate

pip install --upgrade pip wheel setuptools

# =========================
# 4. Instalar NumPy via Termux (evita build)
# =========================
echo ">>> [4/7] Instalando NumPy otimizado..."
pkg install -y python-numpy

# =========================
# 5. Instalar dependências Python
# =========================
echo ">>> [5/7] Instalando dependências Python..."

export CMAKE_ARGS="-DGGML_OPENBLAS=on -DGGML_NATIVE=on"
export FORCE_CMAKE=1

pip install \
gradio \
soundfile \
thefuzz \
python-Levenshtein \
requests \
tokenizers==0.13.3 \
huggingface-hub \
llama-cpp-python \
faster-whisper

# =========================
# 6. Baixar modelos
# =========================
echo ">>> [6/7] Baixando modelos..."

mkdir -p models/piper

# 🔥 RECOMENDO 3B NO ANDROID
if [ ! -f "models/llama-3-3b.gguf" ]; then
  echo "Baixando Llama 3 3B Q4_K_M..."
  wget https://huggingface.co/bartowski/Meta-Llama-3-3B-Instruct-GGUF/resolve/main/Meta-Llama-3-3B-Instruct-Q4_K_M.gguf \
  -O models/llama-3-3b.gguf
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
