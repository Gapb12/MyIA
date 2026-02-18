#!/bin/bash
set -e
echo "================================================"
echo "🚀 INSTALANDO ECHO TUTOR (TERMUX ARM64 - FIX ONNX + ORJSON)"
echo "================================================"

# 1. Atualizar repositório
echo ">>> [1/8] Atualizando Termux..."
pkg update -y

# 2. Instalar toolchain + onnxruntime nativo do Termux (evita pip build)
echo ">>> [2/8] Instalando toolchain e onnxruntime nativo..."
pkg install -y python git wget tar clang make cmake ninja patchelf autoconf automake libtool pkg-config libopenblas ffmpeg python-numpy libsndfile onnxruntime rust

# 3. Criar venv
echo ">>> [3/8] Criando venv..."
rm -rf venv
python -m venv venv --system-site-packages
source venv/bin/activate
pip install --upgrade pip wheel setuptools

# 4. Instalar Gradio e deps sem orjson/onnnxruntime build pesado
echo ">>> [4/8] Instalando Gradio e deps principais..."
pip install gradio --no-deps --no-build-isolation
pip install httpx jinja2 markupsafe numpy pydantic fastapi uvicorn aiofiles altair pillow pydub typing-extensions

# 5. Instalar faster-whisper, llama, piper (sem onnxruntime do pip)
echo ">>> [5/8] Instalando faster-whisper, llama-cpp-python e piper..."
pip install faster-whisper --no-deps
pip install huggingface-hub tokenizers
export CMAKE_ARGS="-DGGML_OPENBLAS=on -DGGML_NATIVE=on -DGGML_NO_OPENMP=ON"
export FORCE_CMAKE=1
pip install llama-cpp-python --force-reinstall --no-cache-dir
pip install piper-tts --no-deps  # Usa onnxruntime do pkg

# 6. Tentar orjson opcional (se falhar, continua)
echo ">>> [6/8] Tentando orjson opcional..."
pip install orjson==3.9.15 || echo "Orjson falhou - Gradio usa fallback"

# 7. Baixar modelos
echo ">>> [7/8] Baixando modelos..."
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

# 8. Teste e start.sh
echo ">>> [8/8] Testando imports e criando start.sh..."
python -c "import gradio; import faster_whisper; import llama_cpp; import piper_tts; print('Imports OK - onnxruntime do pkg!')"
cat <<EOF > start.sh
#!/bin/bash
source venv/bin/activate
python app.py
EOF
chmod +x start.sh

echo ""
echo "================================================"
echo "✅ INSTALAÇÃO CONCLUÍDA!"
echo "Rode ./start.sh"
echo "Acesse http://127.0.0.1:7860 no browser"
echo "Se erro, rode 'python -c \"import onnxruntime; print('OK')\"' para confirmar onnxruntime"
echo "================================================"
