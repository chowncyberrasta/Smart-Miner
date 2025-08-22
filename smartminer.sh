#!/bin/bash
# ==============================================================================
# --- CONFIGURAÇÕES - EDITE APENAS ESTA SEÇÃO ---
# ==============================================================================

# Onde o hminer será instalado. Mantenha no diretório home para evitar problemas de permissão.
INSTALL_DIR="${HOME}/hminer_install"

# --- Suas Informações de Mineração ---
WALLET_ADDRESS="SUA_CARTEIRA_MONERO_AQUI"
POOL_URL="stratum+tcp://pool.supportxmr.com:443"
WORKER_NAME="meu-servidor-$(hostname -s)"

# --- Comportamento do Controlador ---
# O script vai minerar se a CPU estiver MAIS ociosa que este valor (%).
# 80% ociosa = 20% de uso.
IDLE_THRESHOLD=80

# Número de threads da CPU para usar na mineração.
# Use o comando 'nproc' no seu servidor para ver quantos núcleos você tem e defina um valor menor do que o máximo.
CPU_THREADS=2

# Intervalo em segundos entre as verificações de uso da CPU.
CHECK_INTERVAL_SECONDS=60

# ==============================================================================
# --- FIM DAS CONFIGURAÇÕES - NÃO EDITE ABAIXO DESTA LINHA ---
# ==============================================================================

# --- Variáveis Internas ---
HMINER_EXEC_PATH="${INSTALL_DIR}/hminer/hminer"
PID_FILE="/tmp/hminer_controller.pid"

# --- Função de Setup: Prepara o ambiente e compila o hminer ---
setup_hminer() {
    echo "--- [FASE DE SETUP] ---"
    
    # Verifica se o hminer já está compilado
    if [ -f "$HMINER_EXEC_PATH" ]; then
        echo "✓ O hminer já está instalado em $HMINER_EXEC_PATH."
        echo "--- [SETUP CONCLUÍDO] ---"
        return 0
    fi

    echo "hminer não encontrado. Iniciando instalação..."

    # Verifica dependências essenciais
    echo -n "Verificando dependências (git, gcc)... "
    if ! command -v git &> /dev/null || ! command -v gcc &> /dev/null; then
        echo "ERRO!"
        echo "Dependências essenciais não encontradas."
        echo "Por favor, execute o seguinte comando manualmente e rode o script de novo:"
        echo "sudo apt-get update && sudo apt-get install -y git build-essential automake libssl-dev libcurl4-openssl-dev libjansson-dev libgmp-dev"
        exit 1
    fi
    echo "OK."

    # Cria diretório de instalação e clona o repositório
    echo "Criando diretório de instalação em $INSTALL_DIR..."
    mkdir -p "$INSTALL_DIR"
    cd "$INSTALL_DIR"

    echo "Baixando o código-fonte do hminer..."
    git clone https://github.com/hellcatz/hminer.git
    
    if [ ! -d "hminer" ]; then
        echo "ERRO: Falha ao clonar o repositório do hminer."
        exit 1
    fi
    
    cd hminer

    # Compila
    echo "Compilando o hminer... (isso pode levar alguns minutos)"
    if ! ./build.sh; then
        echo "ERRO: A compilação falhou. Verifique as mensagens de erro acima."
        exit 1
    fi

    # Verificação final
    if [ -f "$HMINER_EXEC_PATH" ]; then
        echo "✓ Compilação concluída com sucesso!"
    else
        echo "ERRO: Arquivo executável não encontrado após a compilação."
        exit 1
    fi
    
    echo "--- [SETUP CONCLUÍDO] ---"
    cd "$HOME" # Retorna para o diretório inicial
}

# --- Funções do Controlador de Mineração ---
is_miner_running() {
    if [ -f "$PID_FILE" ]; then
        local PID=$(cat "$PID_FILE")
        if [ -n "$PID" ] && kill -0 "$PID" > /dev/null 2>&1; then
            return 0
        fi
    fi
    return 1
}

start_miner() {
    if is_miner_running; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Verificação: Mineração já está ativa."
        return
    fi

    echo "$(date '+%Y-%m-%d %H:%M:%S') - CPU ociosa. Iniciando mineração..."
    "$HMINER_EXEC_PATH" -o "$POOL_URL" -u "$WALLET_ADDRESS" -p "$WORKER_NAME" -t "$CPU_THREADS" -B > /dev/null 2>&1
    local HMINER_PID=$!
    echo "$HMINER_PID" > "$PID_FILE"
    sleep 1
    
    if is_miner_running; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - hminer iniciado com PID: $HMINER_PID"
    else
        echo "$(date '+%Y-%m-%d %H:%M:%S') - ERRO: Falha ao iniciar o hminer."
        rm -f "$PID_FILE"
    fi
}

stop_miner() {
    if ! is_miner_running; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Verificação: Mineração já está parada."
        return
    fi

    local PID=$(cat "$PID_FILE")
    echo "$(date '+%Y-%m-%d %H:%M:%S') - CPU em uso. Parando a mineração (PID: $PID)..."
    kill "$PID"
    sleep 5
    if is_miner_running; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Processo não encerrou. Forçando (kill -9)..."
        kill -9 "$PID"
    fi
    
    rm -f "$PID_FILE"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - hminer parado."
}

# --- EXECUÇÃO PRINCIPAL ---

# 1. Roda a fase de setup
setup_hminer

# 2. Inicia o loop do controlador
echo ""
echo "--- Controlador de Mineração (Bash/hminer) Iniciado ---"
echo "Monitorando uso da CPU a cada $CHECK_INTERVAL_SECONDS segundos."
echo "Pressione Ctrl+C para parar o monitoramento (se estiver rodando em primeiro plano)."

while true; do
    CPU_IDLE=$(vmstat 1 2 | tail -1 | awk '{print $15}')
    CPU_USAGE=$((100 - CPU_IDLE))

    echo ""
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Uso atual da CPU: $CPU_USAGE% (Ociosa: $CPU_IDLE%)"

    if [ "$CPU_IDLE" -gt "$IDLE_THRESHOLD" ]; then
        start_miner
    else
        stop_miner
    fi

    sleep "$CHECK_INTERVAL_SECONDS"
done
