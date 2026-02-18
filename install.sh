#!/bin/bash
set -e

echo "================================================"
echo "🚀 INSTALANDO ECHO TUTOR - VERSÃO REVISA DA FINAL (COM OPENAI-WHISPER FALLBACK)"
echo "================================================"

# 1. Atualizar repositório
echo ">>> [1/9] Atualizando Termux..."
pkg update -y

# 2. Instalando pacotes do Termux
echo ">>> [2/9] Instalando pacotes do Termux..."
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
  ffmpeg \
  python-numpy \
  libsndfile \
  onnxruntime \
  rust

# 3. Limpando caches
echo ">>> [3/9] Limpando caches..."
rm -rf ~/.cache/pip ~/.cargo/registry/cache ~/.cargo/git

# 4. Criando venv novo
echo ">>> [4/9] Criando venv novo..."
rm -rf venv
python -m venv venv --system-site-packages
source venv/bin/activate
pip install --upgrade pip wheel setuptools --no-cache-dir

# 5. Instalando setuptools-rust (para qualquer build residual)
echo ">>> [5/9] Instalando setuptools-rust..."
pip install setuptools-rust --no-cache-dir

# 6. Instalando Gradio mínimo + client
echo ">>> [6/9] Instalando Gradio e client..."
pip install gradio --no-deps --no-cache-dir --no-build-isolation
pip install gradio-client==2.1.0 --no-cache-dir

# 7. Instalando STT (openai-whisper fallback) e TTS
echo ">>> [7/9] Instalando STT e TTS..."
pip install openai-whisper --no-cache-dir
pip install piper-tts --no-deps --no-cache-dir

# 8. Instalando Llama.cpp
echo ">>> [8/9] Instalando Llama.cpp..."
export CMAKE_ARGS="-DGGML_OPENBLAS=on -DGGML_NATIVE=on -DGGML_NO_OPENMP=ON"
export FORCE_CMAKE=1
pip install llama-cpp-python --force-reinstall --no-cache-dir

# 9. Baixar modelos e testes
echo ">>> [9/9] Baixando modelos e testando..."
# (copia o código de baixar modelos)
mkdir -p models/piper
# Llama 3B
if [ ! -f "models/llama-3-3b.gguf" ]; then
  wget https://huggingface.co/bartowski/Meta-Llama-3-3B-Instruct-GGUF/resolve/main/Meta-Llama-3-3B-Instruct-Q4_K_M.gguf -O models/llama-3-3b.gguf
fi
# Piper e voz
# ... (copia do seu original)

# Testes
python -c "import gradio; import gradio_client; import whisper; import piper_tts; import llama_cpp; print('Imports OK')"

# Criar start.sh
cat <<EOF > start.sh
#!/bin/bash
source venv/bin/activate
python app.py
EOF
chmod +x start.sh

echo "================================================"
echo "✅ INSTALAÇÃO REVISA DA FINALIZADA!"
echo "Rode ./start.sh"
echo "================================================"
