#!/bin/bash
set -e
echo "================================================"
echo "🚀 ECHO TUTOR - INSTALAÇÃO FINAL COM WHISPER.CPP (FUNCIONA NO TERMUX)"
echo "================================================"

echo ">>> Atualizando Termux..."
pkg update -y && pkg upgrade -y

echo ">>> Instalando pacotes necessários..."
pkg install -y git cmake clang make ffmpeg curl python libsndfile

echo ">>> Criando venv limpo..."
rm -rf venv
python -m venv venv --system-site-packages
source venv/bin/activate

pip install --upgrade pip wheel setuptools --no-cache-dir

echo ">>> Instalando Gradio e dependências..."
pip install huggingface-hub==0.23.4 --no-cache-dir
pip install gradio gradio-client httpx jinja2 markupsafe numpy pydantic fastapi uvicorn aiofiles altair pillow pydub typing-extensions thefuzz --no-cache-dir

echo ">>> Compilando whisper.cpp (isso leva 3-8 minutos no celular)..."
cd \~
rm -rf whisper.cpp
git clone --depth 1 https://github.com/ggerganov/whisper.cpp.git
cd whisper.cpp

# Modelo base.en (leve e bom para inglês)
bash models/download-ggml-model.sh base.en

# Build otimizado para Termux
cmake -S . -B build -DGGML_NO_OPENMP=ON
cmake --build build -j2

echo "✅ whisper.cpp compilado com sucesso!"

cd \~/MyIA

echo ">>> Criando start.sh..."
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
echo "Acesse http://127.0.0.1:7860 no navegador do celular"
echo "================================================"