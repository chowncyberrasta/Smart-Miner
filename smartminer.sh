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
WORKER_NAME="meu-servidor-$(hostname -s)"

# --- Comportamento do Controlador ---
# O script vai minerar se a CPU estiver MAIS ociosa que este valor (%).
IDLE_THRESHOLD=90

# Número de threads da CPU para usar.
CPU_THREADS=2

# ==============================================================================
# --- FIM DAS CONFIGURAÇÕES - NÃO EDITE ABAIXO DESTA LINHA ---
# ==============================================================================

# Garante que o script e seus comandos sejam executados a partir do diretório home
cd "${HOME}"

# --- Variáveis Internas ---
XMRIG_DIR_NAME="xmrig-${XMRIG_VERSION}"
XMRIG_EXEC_PATH="${INSTALL_DIR}/${XMRIG_DIR_NAME}/xmrig"
XMRIG_ARCHIVE_NAME="${XMRIG_DIR_NAME}-linux-x64.tar.gz"
XMRIG_DOWNLOAD_URL="https://github.com/xmrig/xmrig/releases/download/v${XMRIG_VERSION}/${XMRIG_ARCHIVE_NAME}"
PID_FILE="/tmp/xmrig_controller.pid"

# --- Função de Setup: Baixa e descompacta o XMRig ---
setup_xmrig() {
    if [ -f "$XMRIG_EXEC_PATH" ]; then return 0; fi
    mkdir -p "$INSTALL_DIR"
    cd "$INSTALL_DIR"
    if ! command -v wget &> /dev/null; then echo "ERRO: wget não encontrado."; exit 1; fi
    wget "$XMRIG_DOWNLOAD_URL"
    tar -zxvf "$XMRIG_ARCHIVE_NAME"
    rm "$XMRIG_ARCHIVE_NAME"
    if [ ! -f "$XMRIG_EXEC_PATH" ]; then echo "ERRO na instalação do XMRig."; exit 1; fi
    cd "${HOME}"
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
    if is_miner_running; then return; fi
    "$XMRIG_EXEC_PATH" --url "$POOL_URL" --user "$WALLET_ADDRESS" --pass "$WORKER_NAME" --keepalive --threads="$CPU_THREADS" --background > /dev/null 2>&1
    local XMRIG_PID=$!
    echo "$XMRIG_PID" > "$PID_FILE"
}

stop_miner() {
    if ! is_miner_running; then return; fi
    local PID=$(cat "$PID_FILE")
    kill "$PID"
    sleep 3
    if is_miner_running; then kill -9 "$PID"; fi
    rm -f "$PID_FILE"
}

setup_xmrig

# Coleta os dados de uso da CPU
CPU_IDLE=$(vmstat 1 2 | tail -1 | awk '{print $15}')

if [ "$CPU_IDLE" -gt "$IDLE_THRESHOLD" ]; then
    start_miner
else
    stop_miner
fi

exit 0
