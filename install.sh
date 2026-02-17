#!/bin/bash

# Para o script se houver qualquer erro (assim você não acha que instalou se falhar)
set -e

echo ">>> 🚀 INICIANDO INSTALAÇÃO DO ECHO TUTOR (S23 ULTRA) <<<"

# 1. Atualizar Termux e Instalar Dependências do Sistema
echo ">>> [1/6] Atualizando pacotes do sistema..."
pkg update -y && pkg upgrade -y
# ADICIONADO: 'pkg-config' (essencial para o erro do av) e 'libjpeg-turbo' (para evitar erros de imagem)
pkg install python git rust binutils build-essential cmake clang libopenblas libandroid-execinfo ffmpeg wget tar ninja python-numpy pkg-config libjpeg-turbo -y

# 2. Configurar Ambiente Virtual Python
echo ">>> [2/6] Criando ambiente virtual Python..."
if [ ! -d "venv" ]; then
    # Usa --system-site-packages para aproveitar o numpy e outros pacotes do Termux
    python -m venv venv --system-site-packages
    echo "Ambiente criado."
fi
source venv/bin/activate

# 3. Instalar Bibliotecas Python
echo ">>> [3/6] Instalando bibliotecas..."
pip install --upgrade pip wheel

# --- CORREÇÃO CRÍTICA DO ERRO 'AV' ---
echo ">>> Instalando PyAV compatível com FFmpeg 7..."
# Força versão recente que suporta o FFmpeg novo do Termux
pip install "av>=13.0.0" --no-binary av

# Instala o restante (o faster-whisper vai usar o 'av' que acabamos de instalar)
pip install -r requirements.txt

echo ">>> Compilando Llama.cpp (Otimizado para Snapdragon)..."
CMAKE_ARGS="-DGGML_OPENBLAS=on" pip install llama-cpp-python --force-reinstall --upgrade --no-cache-dir

# 4. Baixar Modelos
echo ">>> [4/6] Baixando IA e Voz (5GB total)..."
mkdir -p models/piper

# Llama-3 (Cérebro)
if [ ! -f "models/llama-3-8b.gguf" ]; then
    echo "Baixando Llama-3 (Isso pode demorar)..."
    wget https://huggingface.co/bartowski/Meta-Llama-3-8B-Instruct-GGUF/resolve/main/Meta-Llama-3-8B-Instruct-Q4_K_M.gguf -O models/llama-3-8b.gguf
else
    echo "Llama-3 já existe. Pulando download."
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

# 5. Criar o inicializador start.sh
echo ">>> [5/6] Criando script de inicialização..."
echo '#!/bin/bash
source venv/bin/activate
python app.py' > start.sh
chmod +x start.sh

# 6. CONFIGURAÇÃO AUTOMÁTICA DO WIDGET
echo ">>> [6/6] Configurando Atalho na Tela Inicial..."

DIR_ATUAL=$(pwd)

# Script Python para criar o atalho com segurança
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
print(f"✅ Widget criado apontando para: {projeto_dir}")
EOF

python setup_widget.py
rm setup_widget.py

echo " "
echo "================================================"
echo "🎉 TUDO PRONTO! AGORA FAÇA ISSO:"
echo "1. Vá para a tela inicial do celular."
echo "2. Adicione o Widget 'Termux:Widget'."
echo "3. O botão 'Professor' já estará lá funcionando!"
echo "================================================"
