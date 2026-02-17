#!/bin/bash
# Para o script imediatamente se houver erro
set -e
echo ">>> 🚀 INICIANDO INSTALAÇÃO DO ECHO TUTOR (S23 ULTRA - FIX FFmpeg 7 + CT2 BUILD) <<<"

# 1. Atualizar Termux e Instalar Dependências
echo ">>> [1/7] Atualizando pacotes do sistema..."
pkg update -y && pkg upgrade -y
pkg install python git rust binutils build-essential cmake clang libopenblas libandroid-execinfo ffmpeg wget tar ninja python-numpy pkg-config libjpeg-turbo -y

# 2. Configurar Ambiente Virtual
echo ">>> [2/7] Criando ambiente virtual Python..."
if [ ! -d "venv" ]; then
    python -m venv venv --system-site-packages
fi
source venv/bin/activate

# 3. Instalar Bibliotecas Python Básicas
echo ">>> [3/7] Instalando bibliotecas básicas..."
pip install --upgrade pip wheel setuptools
pip install "av>=13.0.0" --no-binary av  # Fix FFmpeg 7 compatível
pip install gradio soundfile thefuzz[similarity] python-Levenshtein requests

# 4. Build Local do CTranslate2 (se não existir)
echo ">>> [4/7] Build local do CTranslate2 para ARM64 Android..."
CT2_DIR="CTranslate2"
if [ ! -f "/data/data/com.termux/files/usr/lib/libctranslate2.so" ]; then
    git clone --recursive https://github.com/OpenNMT/CTranslate2.git $CT2_DIR
    cd $CT2_DIR
    git submodule update --init --recursive
    mkdir build && cd build
    cmake .. -DCMAKE_BUILD_TYPE=Release -DOPENMP_RUNTIME=COMP -DWITH_OPENBLAS=ON -DOPENBLAS_ROOT=/data/data/com.termux/files/usr -DWITH_MKL=OFF -DWITH_RUY=ON -DCMAKE_INSTALL_PREFIX=/data/data/com.termux/files/usr
    make -j$(nproc)
    make install
    cd ../python
    pip install -v -U .  # Instala o wheel Python local
    cd ../..
else
    echo "CTranslate2 já compilado e instalado. Pulando..."
fi

# 5. Instalar Faster-Whisper e Dependências
echo ">>> [5/7] Instalando Faster-Whisper e deps..."
pip install faster-whisper huggingface-hub tokenizers onnxruntime

# 6. Compilar e Instalar Llama.cpp
echo ">>> [6/7] Compilando Llama.cpp (Otimizado para Snapdragon)..."
CMAKE_ARGS="-DGGML_OPENBLAS=on" pip install llama-cpp-python --force-reinstall --upgrade --no-cache-dir

# 7. Baixar Modelos
echo ">>> [7/7] Baixando IA e Voz (5GB total)..."
mkdir -p models/piper
# Llama-3 (use link atualizado de 2026 para Q4_K_M)
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

# 8. Criar inicializador
echo ">>> Criando script de inicialização..."
echo '#!/bin/bash
source venv/bin/activate
python app.py' > start.sh
chmod +x start.sh

# 9. Widget Automático
echo ">>> Configurando Widget..."
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
echo "🎉 TUDO PRONTO! TENTE RODAR O APP COM ./start.sh"
echo "================================================"
