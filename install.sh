#!/bin/bash
set -e
echo "================================================"
echo "🚀 ECHO TUTOR - INSTALAÇÃO FINAL (GRÁDIO 4.44 + WHISPER.CPP)"
echo "================================================"

echo ">>> [1/8] Atualizando Termux..."
pkg update -y && pkg upgrade -y

echo ">>> [2/8] Instalando pacotes base..."
pkg install -y git cmake clang make ffmpeg curl python libsndfile

echo ">>> [3/8] Limpando caches Rust/Temp..."
rm -rf \~/.cargo/registry/cache \~/.cargo/git /tmp/pip* /tmp/tmp* || true
pkill -f cargo || true
pkill -f rustc || true

echo ">>> [4/8] Criando venv limpo..."
rm -rf venv
python -m venv venv --system-site-packages
source venv/bin/activate

pip install --upgrade pip wheel setuptools --no-cache-dir

echo ">>> [5/8] Forçando versões sem Rust..."
pip install pydantic==1.10.12 --no-deps --no-cache-dir
pip install huggingface-hub==0.23.4 --no-deps --no-cache-dir
pip install gradio==4.44.0 --no-deps --no-cache-dir
pip install gradio-client==1.5.2 --no-deps --no-cache-dir

echo ">>> [6/8] Demais dependências..."
pip install httpx jinja2 markupsafe numpy pydantic fastapi uvicorn aiofiles altair pillow pydub typing-extensions thefuzz --no-cache-dir

echo ">>> [7/8] Compilando whisper.cpp..."
cd \~
rm -rf whisper.cpp
git clone --depth 1 https://github.com/ggerganov/whisper.cpp.git
cd whisper.cpp
bash models/download-ggml-model.sh base.en

cmake -S . -B build -DGGML_NO_OPENMP=ON -DCMAKE_BUILD_TYPE=Release
cmake --build build -j2

echo "✅ whisper.cpp pronto!"

cd \~/MyIA

echo ">>> [8/8] Criando start.sh..."
cat <<EOF > start.sh
#!/bin/bash
source venv/bin/activate
python app.py
EOF
chmod +x start.sh

echo ""
echo "================================================"
echo "✅ INSTALAÇÃO CONCLUÍDA!"
echo "Rode: ./start.sh"
echo "Acesse: http://127.0.0.1:7860 no navegador do celular"
echo "================================================"