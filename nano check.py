import os
import sys

print(">>> 🕵️ INICIANDO DIAGNÓSTICO DO ECHO TUTOR...\n")

# 1. Verificar Bibliotecas Python
pacotes = [
    ("faster_whisper", "Ouvido (Whisper)"),
    ("llama_cpp", "Cérebro (Llama)"),
    ("gradio", "Interface (Gradio)"),
    ("thefuzz", "Comparador (Fuzzy)"),
    ("soundfile", "Áudio (Soundfile)")
]

print("[1/3] Verificando Bibliotecas Python...")
erros_lib = False
for pacote, nome in pacotes:
    try:
        __import__(pacote)
        print(f"  ✅ {nome}: OK")
    except ImportError:
        print(f"  ❌ {nome}: FALHOU (Não instalado)")
        erros_lib = True

# 2. Verificar Arquivos de Modelo (Tamanho e Existência)
print("\n[2/3] Verificando Arquivos de IA (Modelos)...")
arquivos = [
    ("models/llama-3-8b.gguf", 4000), # Esperado > 4GB
    ("models/piper/piper", 0.01),     # Binário pequeno
    ("models/piper/en_US-amy-medium.onnx", 50) # ~60MB
]

erros_arq = False
for caminho, tamanho_min_mb in arquivos:
    if os.path.exists(caminho):
        tamanho_atual = os.path.getsize(caminho) / (1024 * 1024) # Em MB
        if tamanho_atual > tamanho_min_mb:
            print(f"  ✅ {caminho}: OK ({tamanho_atual:.1f} MB)")
        else:
            print(f"  ⚠️ {caminho}: CORROMPIDO (Muito pequeno: {tamanho_atual:.1f} MB)")
            erros_arq = True
    else:
        print(f"  ❌ {caminho}: NÃO ENCONTRADO")
        erros_arq = True

# 3. Verificar Permissões
print("\n[3/3] Verificando Permissões...")
if os.path.exists("models/piper/piper"):
    if os.access("models/piper/piper", os.X_OK):
        print("  ✅ Piper é executável: OK")
    else:
        print("  ⚠️ Piper não é executável (Falta chmod +x)")
        # Tenta corrigir automaticamente
        os.system("chmod +x models/piper/piper")
        print("  🔧 Correção automática aplicada.")

print("\n" + "="*30)
if erros_lib or erros_arq:
    print("CONCLUSÃO: ❌ O sistema TEM PROBLEMAS.")
    print("Recomendo rodar o ./install.sh novamente ou instalar o que falta.")
else:
    print("CONCLUSÃO: ✅ TUDO PERFEITO! Pode rodar o ./start.sh")
print("="*30)
