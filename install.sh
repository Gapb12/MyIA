#!/bin/bash
set -e
echo "================================================"
echo "🚀 ECHO TUTOR - INSTALAÇÃO 100% FUNCIONAL (FEVEREIRO 2026)"
echo "================================================"

echo ">>> [1/9] Atualizando Termux..."
pkg update -y && pkg upgrade -y

echo ">>> [2/9] Instalando pacotes essenciais..."
pkg install -y git cmake clang make ffmpeg curl python libsndfile libandroid-spawn ninja patchelf python-numpy libjpeg-turbo libpng rust

echo ">>> [3/9] Limpando caches..."
rm -rf \~/.cache/pip \~/.cargo/registry/cache \~/.cargo/git /tmp/pip* || true

echo ">>> [4/9] Criando venv limpo..."
rm -rf venv
python -m venv venv --system-site-packages
source venv/bin/activate

pip install --upgrade pip wheel setuptools --no-cache-dir

echo ">>> [5/9] Instalando maturin + backends..."
pip install maturin pybind11 scikit-build-core --no-cache-dir

echo ">>> [6/9] Instalando Gradio estável (resolve TypeError e localhost)..."
pip install pydantic==1.10.12 huggingface-hub==0.23.4 --no-deps --no-cache-dir
pip install gradio==3.50.2 gradio-client==0.6.0 --no-deps --no-cache-dir

echo ">>> [7/9] Demais dependências..."
pip install httpx jinja2 markupsafe numpy fastapi uvicorn aiofiles altair pillow pydub typing-extensions thefuzz requests websockets orjson pytz tqdm fsspec pyyaml filelock packaging semantic_version python-multipart ffmpy tomlkit typer safehttpx brotli pandas --no-cache-dir --no-build-isolation

echo ">>> [8/9] Compilando whisper.cpp (4-8 minutos)..."
cd \~
rm -rf whisper.cpp
git clone --depth 1 https://github.com/ggerganov/whisper.cpp.git
cd whisper.cpp
bash models/download-ggml-model.sh base.en

cmake -S . -B build -DGGML_NO_OPENMP=ON -DCMAKE_BUILD_TYPE=Release
cmake --build build -j2

echo "✅ whisper.cpp compilado!"

echo ">>> [9/9] Baixando modelos e criando start.sh..."
cd \~/MyIA
mkdir -p models/piper
wget https://github.com/rhasspy/piper/releases/download/v1.2.0/piper_linux_aarch64.tar.gz -O /tmp/piper.tar.gz
tar -xvf /tmp/piper.tar.gz -C models/piper --strip-components=1
rm /tmp/piper.tar.gz
chmod +x models/piper/piper
wget https://huggingface.co/rhasspy/piper-voices/resolve/main/en/en_US/amy/medium/en_US-amy-medium.onnx -O models/piper/en_US-amy-medium.onnx
wget https://huggingface.co/rhasspy/piper-voices/resolve/main/en/en_US/amy/medium/en_US-amy-medium.onnx.json -O models/piper/en_US-amy-medium.onnx.json

wget https://huggingface.co/bartowski/Phi-3-mini-4k-instruct-GGUF/resolve/main/Phi-3-mini-4k-instruct-Q4_K_M.gguf -O models/phi-3-mini-Q4_K_M.gguf

cat <<EOF > start.sh
#!/bin/bash
source venv/bin/activate
python app.py
EOF
chmod +x start.sh

echo ""
echo "================================================"
echo "✅ INSTALAÇÃO COMPLETA!"
echo "Rode agora: ./start.sh"
echo "Acesse: http://127.0.0.1:7860"
echo "================================================"