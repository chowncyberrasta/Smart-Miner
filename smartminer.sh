#!/bin/bash
# ==============================================================================
# --- CONFIGURAÇÕES - EDITE APENAS ESTA SEÇÃO ---
# ==============================================================================

# --- Configurações do XMRig ---
XMRIG_VERSION="6.21.3"
INSTALL_DIR="${HOME}/xmrig_miner"

# --- Suas Informações de Mineração ---
WALLET_ADDRESS="SUA_CARTEIRA_MONERO_AQUI"
POOL_URL="pool.supportxmr.com:443"
WORKER_NAME="meu-servidor-$(hostname -s)" # Usa o nome do host como nome do worker

# --- Comportamento do Controlador ---
# O script vai minerar se a CPU estiver MAIS ociosa que este valor (%).
IDLE_THRESHOLD=90

# Número de threads da CPU para usar.
CPU_THREADS=2

# Intervalo em segundos entre as verificações de uso da CPU.
CHECK_INTERVAL_SECONDS=60

# ==============================================================================
# --- FIM DAS CONFIGURAÇÕES - NÃO EDITE ABAIXO DESTA LINHA ---
# ==============================================================================

# --- Variáveis Internas ---
XMRIG_DIR_NAME="xmrig-${XMRIG_VERSION}"
XMRIG_EXEC_PATH="${INSTALL_DIR}/${XMRIG_DIR_NAME}/xmrig"
XMRIG_ARCHIVE_NAME="${XMRIG_DIR_NAME}-linux-x64.tar.gz"
XMRIG_DOWNLOAD_URL="https://github.com/xmrig/xmrig/releases/download/v${XMRIG_VERSION}/${XMRIG_ARCHIVE_NAME}"
PID_FILE="/tmp/xmrig_controller.pid"

# --- Função de Setup: Baixa e descompacta o XMRig ---
setup_xmrig() {
    echo "--- [FASE DE SETUP] ---"
    
    # Verifica se o XMRig eo 'wget' já existem
    if [ -f "$XMRIG_EXEC_PATH" ]; then
        echo "✓ XMRig já está instalado em $XMRIG_EXEC_PATH."
        echo "--- [SETUP CONCLUÍDO] ---"
        return 0
    fi

    echo "XMRig não encontrado. Iniciando download e instalação..."
    if ! command -v wget &> /dev/null; then
        echo "✗ ERRO: O comando 'wget' é necessário para o download, mas não foi encontrado."
        exit 1
    fi

    # Cria o diretório de instalação e entra nele
    mkdir -p "$INSTALL_DIR"
    cd "$INSTALL_DIR"

    # Baixa o arquivo
    echo "Baixando XMRig v${XMRIG_VERSION}..."
    if ! wget "$XMRIG_DOWNLOAD_URL"; then
        echo "✗ ERRO: Falha ao baixar o arquivo. Verifique a URL e sua conexão."
        cd ~
        return 1
    fi

    # Descompacta o arquivo
    echo "Descompactando o arquivo..."
    if ! tar -zxvf "$XMRIG_ARCHIVE_NAME"; then
        echo "✗ ERRO: Falha ao descompactar o arquivo."
        cd ~
        return 1
    fi

    # Limpa o arquivo compactado
    rm "$XMRIG_ARCHIVE_NAME"

    # Verificação final
    if [ -f "$XMRIG_EXEC_PATH" ]; then
        echo "✓ XMRig instalado com sucesso!"
    else
        echo "✗ ERRO: Arquivo executável não encontrado após a instalação."
        cd ~
        return 1
    fi
    
    echo "--- [SETUP CONCLUÍDO] ---"
    cd ~
}

# --- Funções do Controlador de Mineração ---
is_miner_running() {
    if [ -f "$PID_FILE" ]; then
        local PID=$(cat "$PID_FILE")
        if [ -n "$PID" ] && ps -p "$PID" > /dev/null; then
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
    "$XMRIG_EXEC_PATH" --url "$POOL_URL" --user "$WALLET_ADDRESS" --pass "$WORKER_NAME" --keepalive --threads="$CPU_THREADS" --background > /dev/null 2>&1
    local XMRIG_PID=$!
    echo "$XMRIG_PID" > "$PID_FILE"
    sleep 1
    if is_miner_running; then echo "$(date '+%Y-%m-%d %H:%M:%S') - XMRig iniciado com PID: $XMRIG_PID"; else echo "$(date '+%Y-%m-%d %H:%M:%S') - ERRO: Falha ao iniciar o XMRig."; rm -f "$PID_FILE"; fi
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
    if is_miner_running; then kill -9 "$PID"; fi
    rm -f "$PID_FILE"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - XMRig parado."
}


# --- EXECUÇÃO PRINCIPAL ---

# Roda a fase de setup
setup_xmrig

# Inicia o loop do controlador
echo ""
echo "--- Controlador de Mineração 'Plug-and-Play' Iniciado ---"
echo "Monitorando uso da CPU a cada $CHECK_INTERVAL_SECONDS segundos."

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
