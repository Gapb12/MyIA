#!/bin/bash

# Para o script imediatamente se houver erro
set -e

echo ">>> 🚀 INICIANDO INSTALAÇÃO DO ECHO TUTOR (S23 ULTRA - FIX FFmpeg 7) <<<"

# 1. Atualizar Termux e Instalar Dependências
echo ">>> [1/6] Atualizando pacotes do sistema..."
pkg update -y && pkg upgrade -y
# Adicionamos pkg-config e libjpeg-turbo para garantir compatibilidade
pkg install python git rust binutils build-essential cmake clang libopenblas libandroid-execinfo ffmpeg wget tar ninja python-numpy pkg-config libjpeg-turbo -y

# 2. Configurar Ambiente Virtual
echo ">>> [2/6] Criando ambiente virtual Python..."
if [ ! -d "venv" ]; then
    # --system-site-packages usa o numpy pré-instalado do Termux (evita erro de compilação)
    python -m venv venv --system-site-packages
fi
source venv/bin/activate

# 3. Instalar Bibliotecas Python (A CIRURGIA COMEÇA AQUI)
echo ">>> [3/6] Instalando bibliotecas..."
pip install --upgrade pip wheel

echo ">>> 🔧 Aplicando correção para FFmpeg 7..."

# PASSO A: Força a instalação do PyAV moderno (compatível com Termux novo)
# A versão 13+ suporta FFmpeg 7.0
pip install "av>=13.0.0" --no-binary av

# PASSO B: Instala o faster-whisper SEM DEPENDÊNCIAS
# Isso impede que ele tente baixar o 'av' velho e quebre tudo
pip install faster-whisper --no-deps

# PASSO C: Instala manualmente os amigos do faster-whisper que ficaram faltando
# (Já que usamos --no-deps, precisamos instalar estes na mão)
pip install ctranslate2 huggingface-hub tokenizers onnxruntime

# PASSO D: Instala o resto do app
pip install gradio soundfile thefuzz levenshtein requests

echo ">>> Compilando Llama.cpp (Otimizado para Snapdragon)..."
CMAKE_ARGS="-DGGML_OPENBLAS=on" pip install llama-cpp-python --force-reinstall --upgrade --no-cache-dir

# 4. Baixar Modelos
echo ">>> [4/6] Baixando IA e Voz (5GB total)..."
mkdir -p models/piper

# Llama-3 (Cérebro)
if [ ! -f "models/llama-3-8b.gguf" ]; then
    echo "Baixando Llama-3 (Isso demora)..."
    wget https://huggingface.co/bartowski/Meta-Llama-3-8B-Instruct-GGUF/resolve/main/Meta-Llama-3-8B-Instruct-Q4_K_M.gguf -O models/llama-3-8b.gguf
else
    echo "Llama-3 já baixado."
fi

# Piper (Motor de Voz)
if [ ! -f "models/piper/piper" ]; then
    echo "Baixando motor de voz Piper..."
    wget https://github.com/rhasspy/piper/releases/download/v1.2.0/piper_linux_aarch64.tar.gz
    tar -xvf piper_linux_aarch64.tar.gz -C models/
    rm piper_linux_aarch64.tar.gz
    if [ -d "models/piper_linux_aarch64" ]; then
        mv models/piper_linux_aarch64/* models/piper/
        rmdir models/piper_linux_aarch64
    fi
else
    echo "Piper já instalado."
fi

# Voz da Amy
if [ ! -f "models/piper/en_US-amy-medium.onnx" ]; then
    echo "Baixando voz (Amy)..."
    wget https://huggingface.co/rhasspy/piper-voices/resolve/main/en/en_US/amy/medium/en_US-amy-medium.onnx -O models/piper/en_US-amy-medium.onnx
    wget https://huggingface.co/rhasspy/piper-voices/resolve/main/en/en_US/amy/medium/en_US-amy-medium.onnx.json -O models/piper/en_US-amy-medium.onnx.json
fi

# 5. Criar inicializador
echo ">>> [5/6] Criando script de inicialização..."
echo '#!/bin/bash
source venv/bin/activate
python app.py' > start.sh
chmod +x start.sh

# 6. Widget Automático
echo ">>> [6/6] Configurando Widget..."
DIR_ATUAL=$(pwd)
cat <<EOF > setup_widget.py
import os
import stat
atalho_dir = os.path.expanduser("~/.shortcuts")
atalho_path = os.path.join(atalho_dir, "Professor")
projeto_dir = "$DIR_ATUAL"
if not os.path.exists(atalho_dir):
    os.makedirs(atalho_dir)
conteudo = f"#!/bin/bash\ncd {projeto_dir} && ./start.sh\n"
with open(atalho_path, "w") as f:
    f.write(conteudo)
st = os.stat(atalho_path)
os.chmod(atalho_path, st.st_mode | stat.S_IEXEC)
print(f"✅ Widget criado em: {atalho_path}")
EOF
python setup_widget.py
rm setup_widget.py

echo " "
echo "================================================"
echo "🎉 TUDO PRONTO! TENTE RODAR O APP."
echo "================================================"
