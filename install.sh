#!/bin/bash
set -e
echo "================================================"
echo "🚀 INSTALANDO ECHO TUTOR (TERMUX ARM64 COMPLETO - FIXES 2026)"
echo "================================================"

# 1. Atualizar repositório
echo ">>> [1/8] Atualizando Termux..."
pkg update -y

# 2. Instalar toolchain COMPLETA + extras para onnxruntime build
echo ">>> [2/8] Instalando toolchain completa..."
pkg install -y python git wget tar clang make cmake ninja patchelf autoconf automake libtool pkg-config libopenblas ffmpeg python-numpy libsndfile onnxruntime

# 3. Criar ambiente virtual
echo ">>> [3/8] Criando ambiente virtual..."
rm -rf venv  # Limpa se existir
python -m venv venv --system-site-packages
source venv/bin/activate
pip install --upgrade pip wheel setuptools

# 4. Instalar dependências Python com downgrades para compatibilidade
echo ">>> [4/8] Instalando dependências Python..."
export CMAKE_ARGS="-DGGML_OPENBLAS=on -DGGML_NATIVE=on -DGGML_NO_OPENMP=ON"  # Fix estabilidade no Termux
export FORCE_CMAKE=1
pip install gradio soundfile thefuzz python-Levenshtein requests tokenizers==0.13.3 huggingface-hub
pip install llama-cpp-python --force-reinstall --no-cache-dir  # Recompila com flags
pip install faster-whisper  # Em vez de whisper padrão

# 5. Fix Piper se conflito (instala --no-deps + deps manuais)
echo ">>> [5/8] Instalando Piper-TTS com fix deps..."
pip install onnxruntime==1.14.1  # Downgrade para evitar "libdl.so.2 not found"
pip install piper-tts --no-deps

# 6. Baixar modelos (use 3B leve para mobile)
echo ">>> [6/8] Baixando modelos..."
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

# 7. Teste dependências
echo ">>> [7/8] Testando imports..."
python -c "import faster_whisper; import llama_cpp; import piper_tts; print('OK')"

# 8. Criar start.sh
echo ">>> [8/8] Criando start.sh..."
cat <<EOF > start.sh
#!/bin/bash
source venv/bin/activate
python app.py
EOF
chmod +x start.sh

echo "================================================"
echo "✅ INSTALAÇÃO CONCLUÍDA. Rode ./start.sh e acesse http://127.0.0.1:7860 no browser."
echo "Se erro, rode 'bash -x start.sh' para debug."
echo "================================================"
