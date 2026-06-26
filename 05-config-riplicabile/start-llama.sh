#!/bin/bash

# Script di avvio universale per llama-server ottimizzato
# Supporta diverse GPU e configurazioni predefinite

set -e

# Colori per output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Funzioni di logging
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Funzione per verificare prerequisiti
check_prerequisites() {
    log_info "Verifica prerequisiti..."

    # Verifica llama-server
    if ! command -v llama-server &> /dev/null; then
        log_error "llama-server non trovato nell'PATH"
        exit 1
    fi

    # Verifica CUDA
    if ! nvidia-smi &> /dev/null; then
        log_error "NVIDIA CUDA non disponibile o non configurato"
        exit 1
    fi

    # Verifica file di configurazione
    local config_file="$1"
    if [[ ! -f "$config_file" ]]; then
        log_error "File di configurazione non trovato: $config_file"
        exit 1
    fi

    log_success "Prerequisiti soddisfatti"
}

# Funzione per caricare configurazione da JSON
load_config() {
    local config_file="$1"

    if ! command -v jq &> /dev/null; then
        log_error "jq non installato. Installare: sudo apt install jq"
        exit 1
    fi

    # Verifica JSON valido
    if ! jq empty "$config_file" 2>/dev/null; then
        log_error "File JSON non valido: $config_file"
        exit 1
    fi

    # Carica configurazione
    config=$(jq -c '.' "$config_file")

    # Estrai parametri
    model=$(echo "$config" | jq -r '.model')
    port=$(echo "$config" | jq -r '.port')
    ngl=$(echo "$config" | jq -r '.ngl')
    flash_attn=$(echo "$config" | jq -r '.flash_attn')
    cache_type_k=$(echo "$config" | jq -r '.cache_type_k')
    cache_type_v=$(echo "$config" | jq -r '.cache_type_v')
    ctx_size=$(echo "$config" | jq -r '.ctx_size')
    threads=$(echo "$config" | jq -r '.threads')
    parallel=$(echo "$config" | jq -r '.parallel')
    no_warmup=$(echo "$config" | jq -r '.no_warmup')
    metrics=$(echo "$config" | jq -r '.metrics')
    jinja=$(echo "$config" | jq -r '.jinja')
    fit=$(echo "$config" | jq -r '.fit')
    reasoning_budget=$(echo "$config" | jq -r '.reasoning_budget // empty')

    # Verifica file modello
    if [[ ! -f "$model" ]]; then
        log_error "File modello non trovato: $model"
        log_info "Percorso corrente: $(pwd)"
        exit 1
    fi

    log_success "Configurazione caricata da: $config_file"
}

# Funzione per costruire comando llama-server
build_command() {
    local cmd="llama-server"

    # Parametri base
    cmd="$cmd -m \"$model\""
    cmd="$cmd -c $ctx_size"
    cmd="$cmd -ngl $ngl"

    # Flash Attention
    if [[ "$flash_attn" != "null" && "$flash_attn" != "" ]]; then
        cmd="$cmd --flash-attn=$flash_attn"
    fi

    # Cache KV
    if [[ "$cache_type_k" != "null" && "$cache_type_k" != "" ]]; then
        cmd="$cmd --cache-type-k=$cache_type_k"
    fi

    if [[ "$cache_type_v" != "null" && "$cache_type_v" != "" ]]; then
        cmd="$cmd --cache-type-v=$cache_type_v"
    fi

    # Thread CPU
    if [[ "$threads" != "null" && "$threads" != "" ]]; then
        cmd="$cmd --threads $threads"
    fi

    # Parallel processing
    if [[ "$parallel" != "null" && "$parallel" != "" ]]; then
        cmd="$cmd --parallel $parallel"
    fi

    # No warmup
    if [[ "$no_warmup" == true ]]; then
        cmd="$cmd --no-warmup"
    fi

    # Metrics
    if [[ "$metrics" == true ]]; then
        cmd="$cmd --metrics"
    fi

    # Jinja templating
    if [[ "$jinja" == true ]]; then
        cmd="$cmd --jinja"
    fi

    # Fit mode
    if [[ "$fit" != "null" && "$fit" != "" ]]; then
        cmd="$cmd --fit $fit"
    fi

    # Reasoning budget (opzionale)
    if [[ "$reasoning_budget" != "" ]]; then
        cmd="$cmd --reasoning-budget $reasoning_budget"
    fi

    # Porta
    cmd="$cmd -p $port"

    echo "$cmd"
}

# Funzione per avviare servizio
start_service() {
    local cmd="$1"
    local gpu_name=$(nvidia-smi --query-gpu=name --format=%%no%%nput | head -1)

    log_info "Avvio llama-server su porta $port"
    log_info "GPU: $gpu_name"
    log_info "Modello: $model"
    log_info "Contesto: $ctx_size token"
    log_info "Command: $cmd"

    # Crea directory log se non esiste
    mkdir -p logs

    # Avvia servizio in background
    nohup $cmd > "logs/llama-server-$port.log" 2>&1 &
    local pid=$!

    # Salva PID
    echo $pid > "logs/llama-server-$port.pid"

    log_success "Servizio avviato con PID: $pid"
    log_info "Log: logs/llama-server-$port.log"
    log_info "PID file: logs/llama-server-$port.pid"

    # Attendi avvio
    sleep 3

    # Verifica servizio attivo
    if curl -s "http://localhost:$port" > /dev/null; then
        log_success "Servizio attivo su http://localhost:$port"
    else
        log_error "Servizio non risponde su http://localhost:$port"
        log_info "Controllare log: logs/llama-server-$port.log"
        exit 1
    fi
}

# Funzione per fermare servizio
stop_service() {
    local port="$1"
    local pid_file="logs/llama-server-$port.pid"

    if [[ -f "$pid_file" ]]; then
        local pid=$(cat "$pid_file")
        if kill -0 $pid 2>/dev/null; then
            log_info "Fermando servizio con PID: $pid"
            kill $pid
            sleep 2

            # Forza se necessario
            if kill -0 $pid 2>/dev/null; then
                log_warning "Servizio non risponde, terminazione forzata"
                kill -9 $pid
            fi

            rm -f "$pid_file"
            log_success "Servizio fermato"
        else
            log_warning "Servizio non attivo (PID: $pid)"
            rm -f "$pid_file"
        fi
    else
        log_warning "PID file non trovato: $pid_file"
    fi
}

# Funzione per mostrare status
show_status() {
    local port="$1"

    if curl -s "http://localhost:$port" > /dev/null; then
        local gpu_usage=$(nvidia-smi --query-gpu=utilization.gpu --format=%%no%%nput | head -1)
        local vram_usage=$(nvidia-smi --query-gpu=memory.used --format=%%no%%nput | head -1)

        log_success "Servizio ATTIVO su porta $port"
        log_info "GPU Usage: $gpu_usage"
        log_info "VRAM Usage: $vram_usage"
    else
        log_error "Servizio NON ATTIVO su porta $port"
    fi
}

# Funzione per mostrare help
show_help() {
    echo "Usage: $0 [COMMAND] [CONFIG_FILE]"
    echo ""
    echo "Commands:"
    echo "  start <config.json>    Avvia llama-server con configurazione"
    echo "  stop <config.json>     Ferma llama-server con configurazione"
    echo "  restart <config.json>  Riavvia llama-server"
    echo "  status <config.json>   Mostra status del servizio"
    echo "  list                  Elenca configurazioni disponibili"
    echo "  help                  Mostra questo help"
    echo ""
    echo "Configurations:"
    echo "  config-p40.json     Tesla P40 (24GB VRAM) - Modelli 35B+"
    echo "  config-rtx3050.json RTX 3050 (8GB VRAM) - Modelli 9B"
    echo "  config-generale.json Configurazione generica adattabile"
    echo ""
    echo "Examples:"
    echo "  $0 start config-p40.json"
    echo "  $0 stop config-p40.json"
    echo "  $0 status config-rtx3050.json"
}

# Funzione per elencare configurazioni
list_configs() {
    echo "Configurazioni disponibili:"
    echo ""

    for config in config-*.json; do
        if [[ -f "$config" ]]; then
            local model=$(jq -r '.model' "$config")
            local port=$(jq -r '.port' "$config")
            local gpu=$(echo "$config" | sed 's/config-//' | sed 's/.json//')

            echo "  $config"
            echo "    Model: $model"
            echo "    Port: $port"
            echo "    GPU: $gpu"
            echo ""
        fi
    done
}

# Main script
case "${1:-help}" in
    start)
        if [[ -z "$2" ]]; then
            log_error "Specificare file di configurazione"
            show_help
            exit 1
        fi

        check_prerequisites "$2"
        load_config "$2"
        local cmd=$(build_command)
        start_service "$cmd"
        ;;

    stop)
        if [[ -z "$2" ]]; then
            log_error "Specificare file di configurazione"
            show_help
            exit 1
        fi

        load_config "$2"
        stop_service "$port"
        ;;

    restart)
        if [[ -z "$2" ]]; then
            log_error "Specificare file di configurazione"
            show_help
            exit 1
        fi

        log_info "Riavvio servizio..."
        $0 stop "$2"
        sleep 2
        $0 start "$2"
        ;;

    status)
        if [[ -z "$2" ]]; then
            log_error "Specificare file di configurazione"
            show_help
            exit 1
        fi

        load_config "$2"
        show_status "$port"
        ;;

    list)
        list_configs
        ;;

    help|--help|-h)
        show_help
        ;;

    *)
        log_error "Comando non riconosciuto: $1"
        show_help
        exit 1
        ;;
esac