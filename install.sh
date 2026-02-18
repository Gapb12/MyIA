#!/bin/bash
set -e

echo "================================================"
echo "🚀 INSTALANDO ECHO TUTOR - VERSÃO LIMPA E FINAL (COM OPENAI-WHISPER)"
echo "================================================"

# 1. Atualizar repositório
echo ">>> [1/9] Atualizando Termux..."
pkg update -y

# 2. Instalando pacotes do Termux necessários
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
  rust

# 3. Limpando caches para evitar problemas de build
echo ">>> [3/9] Limpando caches..."
rm -rf ~/.cache/pip ~/.cargo/registry/cache ~/.cargo/git

# 4. Criando venv novo
echo ">>> [4/9] Criando venv novo..."
rm -rf venv
python -m venv venv --system-site-packages
source venv/bin/activate
pip install --upgrade pip wheel setuptools --no-cache-dir

# 5. Instalando Gradio e dependências essenciais
echo ">>> [5/9] Instalando Gradio mínimo + client..."
pip install gradio --no-deps --no-cache-dir --no-build-isolation
pip install gradio-client==2.1.0 --no-cache-dir
pip install httpx jinja2 markupsafe numpy pydantic fastapi uvicorn aiofiles altair pillow pydub typing-extensions --no-cache-dir

# 6. Instalando STT (openai-whisper - fallback sem Rust) e TTS
echo ">>> [6/9] Instalando STT e TTS..."
pip install openai-whisper --no-build-isolation --no-cache-dir
pip install piper-tts --no-deps --no-cache-dir

# 7. Instalando Llama.cpp
echo ">>> [7/9] Instalando Llama.cpp..."
export CMAKE_ARGS="-DGGML_OPENBLAS=on -DGGML_NATIVE=on -DGGML_NO_OPENMP=ON"
export FORCE_CMAKE=1
pip install llama-cpp-python --force-reinstall --no-cache-dir

# 8. Baixar modelos
echo ">>> [8/9] Baixando modelos..."
mkdir -p models/piper

# Llama 3B leve
if [ ! -f "models/llama-3-3b.gguf" ]; then
  echo "Baixando Llama-3-3B-Instruct Q4_K_M..."
  wget https://huggingface.co/bartowski/Meta-Llama-3-3B-Instruct-GGUF/resolve/main/Meta-Llama-3-3B-Instruct-Q4_K_M.gguf -O models/llama-3-3b.gguf
fi

# Piper binary
if [ ! -f "models/piper/piper" ]; then
  echo "Baixando Piper binary..."
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
  wget https://huggingface.co/rhasspy/piper-voices/resolve/main/en/en_US/amy/medium/en_US-amy-medium.onnx -O models/piper/en_US-amy-medium.onnx
  wget https://huggingface.co/rhasspy/piper-voices/resolve/main/en/en_US/amy/medium/en_US-amy-medium.onnx.json -O models/piper/en_US-amy-medium.onnx.json
fi

# 9. Testes finais
echo ">>> [9/9] Testando imports críticos..."
python -c "
try:
    import gradio
    print('Gradio OK')
except:
    print('Gradio falhou')
try:
    import gradio_client
    print('Gradio Client OK')
except:
    print('Gradio Client falhou')
try:
    import whisper
    print('Whisper OK')
except:
    print('Whisper falhou')
try:
    import piper_tts
    print('Piper OK')
except:
    print('Piper falhou')
try:
    import llama_cpp
    print('Llama OK')
except:
    print('Llama falhou')
print('Teste concluído')
"

# Criar start.sh
echo ">>> Criando start.sh..."
cat <<EOF > start.sh
#!/bin/bash
source venv/bin/activate
python app.py
EOF
chmod +x start.sh

echo ""
echo "================================================"
echo "✅ INSTALAÇÃO LIMPA COMPLETA!"
echo "Rode ./start.sh para iniciar"
echo "Acesse http://127.0.0.1:7860 no navegador do celular"
echo "================================================"
