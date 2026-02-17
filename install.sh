#!/bin/bash

echo ">>> 🚀 INICIANDO INSTALAÇÃO DO ECHO TUTOR (S23 ULTRA) <<<"

# 1. Atualizar Termux e Instalar Dependências do Sistema
echo ">>> [1/6] Atualizando pacotes do sistema..."
pkg update -y && pkg upgrade -y
pkg install python git rust binutils build-essential cmake clang libopenblas libandroid-execinfo ffmpeg wget tar -y

# 2. Configurar Ambiente Virtual Python
echo ">>> [2/6] Criando ambiente virtual Python..."
if [ ! -d "venv" ]; then
    python -m venv venv
fi
source venv/bin/activate

# 3. Instalar Bibliotecas Python
echo ">>> [3/6] Instalando bibliotecas..."
pip install --upgrade pip
pip install -r requirements.txt

echo ">>> Compilando Llama.cpp (Otimizado para Snapdragon)..."
CMAKE_ARGS="-DGGML_OPENBLAS=on" pip install llama-cpp-python --force-reinstall --upgrade --no-cache-dir

# 4. Baixar Modelos
echo ">>> [4/6] Baixando IA e Voz (5GB total)..."
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

# 5. Criar o inicializador start.sh
echo ">>> [5/6] Criando script de inicialização..."
echo '#!/bin/bash
source venv/bin/activate
python app.py' > start.sh
chmod +x start.sh

# 6. CONFIGURAÇÃO AUTOMÁTICA DO WIDGET (A Mágica Nova)
echo ">>> [6/6] Configurando Atalho na Tela Inicial..."

# Pega o caminho atual da pasta onde o script está rodando
DIR_ATUAL=$(pwd)

# Cria um script Python temporário para gerar o atalho com segurança (sem erro de aspas)
cat <<EOF > setup_widget.py
import os
import stat

# Define caminhos
atalho_dir = os.path.expanduser("~/.shortcuts")
atalho_path = os.path.join(atalho_dir, "Professor")
projeto_dir = "$DIR_ATUAL"

# Cria pasta .shortcuts se não existir
if not os.path.exists(atalho_dir):
    os.makedirs(atalho_dir)

# Escreve o conteúdo do atalho
conteudo = f"#!/bin/bash\ncd {projeto_dir} && ./start.sh\n"
with open(atalho_path, "w") as f:
    f.write(conteudo)

# Torna executável
st = os.stat(atalho_path)
os.chmod(atalho_path, st.st_mode | stat.S_IEXEC)
print(f"✅ Widget criado apontando para: {projeto_dir}")
EOF

# Roda o script e limpa
python setup_widget.py
rm setup_widget.py

echo " "
echo "================================================"
echo "🎉 TUDO PRONTO! AGORA FAÇA ISSO:"
echo "1. Vá para a tela inicial do celular."
echo "2. Adicione o Widget 'Termux:Widget'."
echo "3. O botão 'Professor' já estará lá funcionando!"
echo "================================================"
