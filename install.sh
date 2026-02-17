#!/bin/bash

echo ">>> 🚀 INICIANDO INSTALAÇÃO DO ECHO TUTOR (S23 ULTRA) <<<"

# 1. Atualizar Termux e Instalar Dependências
echo ">>> [1/5] Atualizando sistema..."
pkg update -y && pkg upgrade -y
pkg install python git rust binutils build-essential cmake clang libopenblas libandroid-execinfo ffmpeg wget tar -y

# 2. Configurar Python
echo ">>> [2/5] Criando ambiente virtual..."
if [ ! -d "venv" ]; then
    python -m venv venv
fi
source venv/bin/activate

# 3. Instalar Bibliotecas
echo ">>> [3/5] Instalando bibliotecas..."
pip install --upgrade pip
pip install -r requirements.txt

echo ">>> Compilando Llama.cpp (Isso demora uns 5-10 min)..."
CMAKE_ARGS="-DGGML_OPENBLAS=on" pip install llama-cpp-python --force-reinstall --upgrade --no-cache-dir

# 4. Baixar Modelos
echo ">>> [4/5] Baixando IA e Voz (5GB total)..."
mkdir -p models/piper

# Llama-3 (Cérebro)
if [ ! -f "models/llama-3-8b.gguf" ]; then
    echo "Baixando Llama-3..."
    wget https://huggingface.co/bartowski/Meta-Llama-3-8B-Instruct-GGUF/resolve/main/Meta-Llama-3-8B-Instruct-Q4_K_M.gguf -O models/llama-3-8b.gguf
fi

# Piper (Motor de Voz)
if [ ! -f "models/piper/piper" ]; then
    echo "Baixando motor de voz Piper..."
    wget https://github.com/rhasspy/piper/releases/download/v1.2.0/piper_linux_aarch64.tar.gz
    tar -xvf piper_linux_aarch64.tar.gz -C models/
    # Ajuste de pasta se necessário
    if [ -d "models/piper_linux_aarch64" ]; then
        mv models/piper_linux_aarch64/* models/piper/
        rmdir models/piper_linux_aarch64
    fi
fi

# Voz da Amy
if [ ! -f "models/piper/en_US-amy-medium.onnx" ]; then
    echo "Baixando voz (Amy)..."
    wget https://huggingface.co/rhasspy/piper-voices/resolve/main/en/en_US/amy/medium/en_US-amy-medium.onnx -O models/piper/en_US-amy-medium.onnx
    wget https://huggingface.co/rhasspy/piper-voices/resolve/main/en/en_US/amy/medium/en_US-amy-medium.onnx.json -O models/piper/en_US-amy-medium.onnx.json
fi

# Criar atalho de inicialização
echo '#!/bin/bash
source venv/bin/activate
python app.py' > start.sh
chmod +x start.sh

echo ">>> ✅ INSTALAÇÃO CONCLUÍDA! Digite: ./start.sh"
