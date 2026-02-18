#!/bin/bash
set -e

echo "================================================"
echo "🚀 INSTALANDO ECHO TUTOR - VERSÃO MÍNIMA FUNCIONAL (SEM BUILDS RUST PESADOS)"
echo "================================================"

# 1. Atualizar repositório
echo ">>> [1/8] Atualizando Termux..."
pkg update -y

# 2. Instalar pacotes do Termux + onnxruntime nativo
echo ">>> [2/8] Instalando pacotes do Termux..."
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

# 3. Limpar caches
echo ">>> [3/8] Limpando caches..."
rm -rf ~/.cache/pip ~/.cargo/registry/cache ~/.cargo/git

# 4. Criar venv limpo
echo ">>> [4/8] Criando venv novo..."
rm -rf venv
python -m venv venv --system-site-packages
source venv/bin/activate
pip install --upgrade pip wheel setuptools --no-cache-dir

# 5. Instalar Gradio sem deps pesadas
echo ">>> [5/8] Instalando Gradio mínimo..."
pip install gradio --no-deps --no-cache-dir --no-build-isolation
pip install httpx jinja2 markupsafe numpy pydantic fastapi uvicorn aiofiles altair pillow pydub typing-extensions --no-cache-dir

# 6. Instalar apenas faster-whisper e piper (sem tokenizers/huggingface-hub)
echo ">>> [6/8] Instalando STT e TTS..."
pip install faster-whisper --no-deps --no-cache-dir
pip install piper-tts --no-deps --no-cache-dir

# 7. Instalar llama-cpp-python
echo ">>> [7/8] Instalando Llama.cpp..."
export CMAKE_ARGS="-DGGML_OPENBLAS=on -DGGML_NATIVE=on -DGGML_NO_OPENMP=ON"
export FORCE_CMAKE=1
pip install llama-cpp-python --force-reinstall --no-cache-dir

# 8. Baixar modelos
echo ">>> [8/8] Baixando modelos..."
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

# 9. Testes finais
echo ">>> Testando imports críticos..."
python -c "
try:
    import gradio
    print('Gradio OK')
except:
    print('Gradio falhou')
try:
    import faster_whisper
    print('Faster Whisper OK')
except:
    print('Faster Whisper falhou')
try:
    import llama_cpp
    print('Llama OK')
except:
    print('Llama falhou')
try:
    import piper_tts
    print('Piper OK')
except:
    print('Piper falhou')
print('Teste concluído')
"

# 10. Criar start.sh
echo ">>> Criando start.sh..."
cat <<EOF > start.sh
#!/bin/bash
source venv/bin/activate
python app.py
EOF
chmod +x start.sh

echo ""
echo "================================================"
echo "✅ INSTALAÇÃO MÍNIMA FINALIZADA!"
echo "Rode ./start.sh"
echo "Acesse http://127.0.0.1:7860 no navegador"
echo "Se der erro, cole o traceback do python app.py"
echo "================================================"
