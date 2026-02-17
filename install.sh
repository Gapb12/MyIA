#!/bin/bash

echo ">>> 🚀 INICIANDO INSTALAÇÃO DO ECHO TUTOR (S23 ULTRA EDITION) <<<"

# 1. Atualizar Termux e Instalar Dependências do Sistema
echo ">>> [1/5] Atualizando pacotes do sistema (pode pedir senha ou confirmação)..."
pkg update -y && pkg upgrade -y
pkg install python git rust binutils build-essential cmake clang libopenblas libandroid-execinfo ffmpeg wget tar -y

# 2. Configurar Ambiente Virtual Python
echo ">>> [2/5] Criando ambiente virtual Python..."
if [ ! -d "venv" ]; then
    python -m venv venv
    echo "Ambiente 'venv' criado."
else
    echo "Ambiente 'venv' já existe."
fi

# Ativar ambiente para os próximos comandos
source venv/bin/activate

# 3. Instalar Bibliotecas Python
echo ">>> [3/5] Instalando bibliotecas Python (Isso pode demorar um pouco)..."
pip install --upgrade pip
pip install -r requirements.txt

# Instalação especial do Llama com aceleração de hardware (OpenBLAS para Android)
echo ">>> Compilando Llama.cpp para Snapdragon 8 Gen 2..."
CMAKE_ARGS="-DGGML_OPENBLAS=on" pip install llama-cpp-python --force-reinstall --upgrade --no-cache-dir

# 4. Baixar Modelos (IA e Voz)
echo ">>> [4/5] Baixando modelos de IA (Verificando arquivos)..."
mkdir -p models/piper

# Baixar Llama-3 (Cérebro) - Aprox 4.7GB
if [ ! -f "models/llama-3-8b.gguf" ]; then
    echo "Baixando Llama-3 (pode demorar dependendo da internet)..."
    wget https://huggingface.co/bartowski/Meta-Llama-3-8B-Instruct-GGUF/resolve/main/Meta-Llama-3-8B-Instruct-Q4_K_M.gguf -O models/llama-3-8b.gguf
else
    echo "Llama-3 já baixado."
fi

# Baixar Piper (Motor de Voz)
if [ ! -f "models/piper/piper" ]; then
    echo "Baixando motor de voz Piper..."
    wget https://github.com/rhasspy/piper/releases/download/v1.2.0/piper_linux_aarch64.tar.gz
    tar -xvf piper_linux_aarch64.tar.gz -C models/
    rm piper_linux_aarch64.tar.gz
    # Mover para garantir a estrutura correta se extrair pasta errada
    if [ -d "models/piper_linux_aarch64" ]; then
        mv models/piper_linux_aarch64/* models/piper/
        rmdir models/piper_linux_aarch64
    fi
else
    echo "Piper já instalado."
fi

# Baixar Voz da Amy
if [ ! -f "models/piper/en_US-amy-medium.onnx" ]; then
    echo "Baixando voz (Amy)..."
    wget https://huggingface.co/rhasspy/piper-voices/resolve/main/en/en_US/amy/medium/en_US-amy-medium.onnx -O models/piper/en_US-amy-medium.onnx
    wget https://huggingface.co/rhasspy/piper-voices/resolve/main/en/en_US/amy/medium/en_US-amy-medium.onnx.json -O models/piper/en_US-amy-medium.onnx.json
fi

echo ">>> [5/5] Instalação Concluída com Sucesso! ✅"
echo "Para iniciar, digite: ./start.sh"

# Criar um atalho de inicialização rápida
echo '#!/bin/bash
source venv/bin/activate
python app.py' > start.sh
chmod +x start.sh
