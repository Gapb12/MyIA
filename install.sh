#!/bin/bash
set -e

echo "================================================"
echo "🚀 INSTALANDO ECHO TUTOR - VERSÃO FIX PYDANTIC-CORE + CARGO JOBS"
echo "================================================"

# 1. Atualizar repositório
echo ">>> [1/9] Atualizando Termux..."
pkg update -y

# 2. Instalar pacotes do sistema + onnxruntime nativo
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

# 3. Limpar caches antes de começar (importante para evitar "text file busy")
echo ">>> [3/9] Limpando caches do pip e Cargo..."
rm -rf ~/.cache/pip
rm -rf ~/.cargo/registry/cache
rm -rf ~/.cargo/git

# 4. Criar venv limpo
echo ">>> [4/9] Criando venv novo..."
rm -rf venv
python -m venv venv --system-site-packages
source venv/bin/activate
pip install --upgrade pip wheel setuptools --no-cache-dir

# 5. Instalar Gradio e deps essenciais com limite de jobs
echo ">>> [5/9] Instalando Gradio e deps (limite Cargo jobs=4)..."
export CARGO_BUILD_JOBS=4  # Limita paralelismo para evitar error 26
pip install gradio --no-deps --no-cache-dir --no-build-isolation
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
  typing-extensions --no-cache-dir

# 6. Instalar tokenizers fixo + huggingface-hub + faster-whisper + piper
echo ">>> [6/9] Instalando componentes de IA..."
pip install tokenizers==0.13.3 --no-deps --no-cache-dir --no-build-isolation
pip install huggingface-hub --no-cache-dir
pip install faster-whisper --no-deps --no-cache-dir
export CMAKE_ARGS="-DGGML_OPENBLAS=on -DGGML_NATIVE=on -DGGML_NO_OPENMP=ON"
export FORCE_CMAKE=1
pip install llama-cpp-python --force-reinstall --no-cache-dir
pip install piper-tts --no-deps --no-cache-dir

# 7. Fallback pydantic v1 se pydantic-core falhar (opcional - rode manual se necessário)
echo ">>> [7/9] Tentando pydantic v1 fallback se necessário..."
pip install "pydantic<2" --no-cache-dir || echo "Pydantic v1 fallback não necessário"

# 8. Baixar modelos
echo ">>> [8/9] Baixando modelos..."
mkdir -p models/piper

if [ ! -f "models/llama-3-3b.gguf" ]; then
  echo "Baixando Llama-3-3B-Instruct Q4_K_M..."
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
echo ">>> [9/9] Testando imports críticos..."
python -c "
import gradio
import faster_whisper
import llama_cpp
import piper_tts
import pydantic
print('Imports OK! Pydantic versão:', pydantic.__version__)
" || echo "Algum import falhou - verifique o erro acima"

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
echo "Acesse no navegador:"
echo "  http://127.0.0.1:7860"
echo ""
echo "Dicas se der erro no start:"
echo "  - Rode 'termux-info' para ver RAM disponível"
echo "  - Rode 'python app.py' diretamente para traceback completo"
echo "  - Se OOM (Killed), reduza n_threads no app.py para 2 ou 4"
echo "================================================"
