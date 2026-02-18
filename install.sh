#!/bin/bash
set -e

echo "================================================"
echo "🚀 INSTALANDO ECHO TUTOR - VERSÃO FINAL (TERMUX ARM64 - 2026)"
echo "================================================"

# 1. Atualizar repositório
echo ">>> [1/9] Atualizando Termux..."
pkg update -y

# 2. Instalar dependências do sistema + onnxruntime nativo
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

# 3. Criar ambiente virtual
echo ">>> [3/9] Criando venv..."
rm -rf venv
python -m venv venv --system-site-packages
source venv/bin/activate
pip install --upgrade pip wheel setuptools

# 4. Instalar Gradio e dependências principais (sem orjson pesado)
echo ">>> [4/9] Instalando Gradio e deps essenciais..."
pip install gradio --no-deps --no-build-isolation
pip install \
  httpx \
  jinja2 \
  markupsafe \
  numpy \
  pydantic \
  fastapi \
  uvicorn \
  aiofiles \
  altair \
  pillow \
  pydub \
  typing-extensions

# 5. Instalar tokenizers fixo + huggingface-hub + faster-whisper + piper
echo ">>> [5/9] Instalando componentes de IA..."
# Tokenizers versão com melhor suporte ARM64
pip install tokenizers==0.13.3 --no-deps --no-build-isolation
pip install huggingface-hub
pip install faster-whisper --no-deps
export CMAKE_ARGS="-DGGML_OPENBLAS=on -DGGML_NATIVE=on -DGGML_NO_OPENMP=ON"
export FORCE_CMAKE=1
pip install llama-cpp-python --force-reinstall --no-cache-dir
pip install piper-tts --no-deps

# 6. Opcional: orjson (se falhar, continua sem)
echo ">>> [6/9] Tentando orjson opcional..."
pip install orjson==3.9.15 || echo "Orjson não instalou - Gradio usa fallback"

# 7. Baixar modelos (leve para mobile)
echo ">>> [7/9] Baixando modelos..."
mkdir -p models/piper

# Llama 3B leve
if [ ! -f "models/llama-3-3b.gguf" ]; then
  echo "Baixando Llama-3-3B-Instruct Q4_K_M..."
  wget https://huggingface.co/bartowski/Meta-Llama-3-3B-Instruct-GGUF/resolve/main/Meta-Llama-3-3B-Instruct-Q4_K_M.gguf \
    -O models/llama-3-3b.gguf
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
  wget https://huggingface.co/rhasspy/piper-voices/resolve/main/en/en_US/amy/medium/en_US-amy-medium.onnx \
    -O models/piper/en_US-amy-medium.onnx
  wget https://huggingface.co/rhasspy/piper-voices/resolve/main/en/en_US/amy/medium/en_US-amy-medium.onnx.json \
    -O models/piper/en_US-amy-medium.onnx.json
fi

# 8. Testes finais
echo ">>> [8/9] Testando imports críticos..."
python -c "
import gradio
import faster_whisper
import llama_cpp
import piper_tts
import onnxruntime
print('Todos imports OK! onnxruntime versão:', onnxruntime.__version__)
" || echo "Algum import falhou - verifique o erro acima"

# 9. Criar start.sh
echo ">>> [9/9] Criando start.sh..."
cat <<EOF > start.sh
#!/bin/bash
source venv/bin/activate
python app.py
EOF
chmod +x start.sh

echo ""
echo "================================================"
echo "✅ INSTALAÇÃO FINALIZADA!"
echo ""
echo "Para iniciar:"
echo "  ./start.sh"
echo ""
echo "Acesse no navegador do celular:"
echo "  http://127.0.0.1:7860"
echo ""
echo "Se der erro ao rodar:"
echo "  1. Rode 'bash -x start.sh' para debug"
echo "  2. Verifique RAM (termux-info)"
echo "  3. Cole o erro aqui"
echo "================================================"
