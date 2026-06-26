#!/bin/bash

# Script di benchmark rapido per validare speedup llama.cpp vs Ollama
# Esegue un test semplice e riporta i risultati

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

# Funzione per verificare dipendenze
check_dependencies() {
    log_info "Verifica dipendenze..."

    # Verifica curl
    if ! command -v curl &> /dev/null; then
        log_error "curl non trovato. Installare: sudo apt install curl"
        exit 1
    fi

    # Verifica bc
    if ! command -v bc &> /dev/null; then
        log_error "bc non trovato. Installare: sudo apt install bc"
        exit 1
    fi

    # Verifica jq
    if ! command -v jq &> /dev/null; then
        log_error "jq non trovato. Installare: sudo apt install jq"
        exit 1
    fi

    log_success "Dipendenze soddisfatte"
}

# Funzione per testare Ollama
test_ollama() {
    local model="$1"
    local prompt="$2"
    local iterations="$3"

    log_info "Test Ollama con modello: $model"

    local total_time=0
    local total_tokens=0

    for i in $(seq 1 $iterations); do
        # Misura tempo di risposta
        local start_time=$(date +%s%3N)

        # Richiesta a Ollama
        local response=$(curl -s -X POST "http://localhost:11434/api/generate" \
            -H "Content-Type: application/json" \
            -d "{
                \"model\": \"$model\",
                \"prompt\": \"$prompt\",
                \"stream\": false
            }")

        local end_time=$(date +%s%3N)
        local duration=$((end_time - start_time))

        # Estrai token generati dalla risposta
        local tokens=$(echo "$response" | jq '.eval_count // 0')

        total_time=$((total_time + duration))
        total_tokens=$((total_tokens + tokens))

        log_info "Iterazione $i: $duration ms, $tokens token"
    done

    # Calcola media
    local avg_time=$((total_time / iterations))
    local avg_tokens=$((total_tokens / iterations))
    local tok_per_sec=0

    if [[ $avg_time -gt 0 ]]; then
        tok_per_sec=$(echo "scale=2; $avg_tokens * 1000 / $avg_time" | bc)
    fi

    echo "{\"platform\":\"ollama\",\"model\":\"$model\",\"avg_time_ms\":$avg_time,\"avg_tokens\":$avg_tokens,\"tok_per_sec\":$tok_per_sec}"
}

# Funzione per testare llama.cpp
test_llama_cpp() {
    local model="$1"
    local prompt="$2"
    local iterations="$3"
    local port="$4"

    log_info "Test llama.cpp con modello: $model su porta $port"

    local total_time=0
    local total_tokens=0

    for i in $(seq 1 $iterations); do
        # Misura tempo di risposta
        local start_time=$(date +%s%3N)

        # Richiesta a llama.cpp
        local response=$(curl -s -X POST "http://localhost:$port/completion" \
            -H "Content-Type: application/json" \
            -d "{
                \"prompt\": \"$prompt\",
                \"n_predict\": 128,
                \"temperature\": 0.7,
                \"stop\": [\"</s>\", \"\\n\\n\"]
            }")

        local end_time=$(date +%s%3N)
        local duration=$((end_time - start_time))

        # Estrai token generati dalla risposta
        local tokens=$(echo "$response" | jq '.content | split(" ") | length // 0')

        # Se non riesce a contare gli token, usa una stima basata sulla lunghezza
        if [[ $tokens -eq 0 ]]; then
            local response_text=$(echo "$response" | jq -r '.content // ""')
            tokens=${#response_text}
            tokens=$((tokens / 5))  # Stima approssimativa: 5 caratteri per token
        fi

        total_time=$((total_time + duration))
        total_tokens=$((total_tokens + tokens))

        log_info "Iterazione $i: $duration ms, $tokens token"
    done

    # Calcola media
    local avg_time=$((total_time / iterations))
    local avg_tokens=$((total_tokens / iterations))
    local tok_per_sec=0

    if [[ $avg_time -gt 0 ]]; then
        tok_per_sec=$(echo "scale=2; $avg_tokens * 1000 / $avg_time" | bc)
    fi

    echo "{\"platform\":\"llama.cpp\",\"model\":\"$model\",\"avg_time_ms\":$avg_time,\"avg_tokens\":$avg_tokens,\"tok_per_sec\":$tok_per_sec}"
}

# Funzione principale
main() {
    # Parametri di default
    local model="qwen3.5:9b"
    local prompt="Hello, how are you today?"
    local iterations=3
    local ollama_port=11434
    local llama_cpp_port=8081

    # Sovrascrivi con argomenti se forniti
    if [[ $# -gt 0 ]]; then
        model="$1"
    fi
    if [[ $# -gt 1 ]]; then
        prompt="$2"
    fi
    if [[ $# -gt 2 ]]; then
        iterations="$3"
    fi
    if [[ $# -gt 3 ]]; then
        ollama_port="$4"
    fi
    if [[ $# -gt 4 ]]; then
        llama_cpp_port="$5"
    fi

    log_info "Benchmark rapido: Ollama vs llama.cpp"
    log_info "Modello: $model"
    log_info "Prompt: \"$prompt\""
    log_info "Iterazioni: $iterations"
    log_info ""

    # Verifica dipendenze
    check_dependencies

    # Test Ollama
    log_info "Test Ollama in corso..."
    local ollama_result=$(test_ollama "$model" "$prompt" "$iterations")
    local ollama_tok_per_sec=$(echo "$ollama_result" | jq '.tok_per_sec')

    echo ""

    # Test llama.cpp
    log_info "Test llama.cpp in corso..."
    local llama_cpp_result=$(test_llama_cpp "$model" "$prompt" "$iterations" "$llama_cpp_port")
    local llama_cpp_tok_per_sec=$(echo "$llama_cpp_result" | jq '.tok_per_sec')

    echo ""

    # Calcola speedup
    local speedup=0
    if [[ $(echo "$ollama_tok_per_sec > 0" | bc) -eq 1 ]]; then
        speedup=$(echo "scale=2; $llama_cpp_tok_per_sec / $ollama_tok_per_sec" | bc)
    fi

    # Risultati
    echo "=== RISULTATI BENCHMARK ==="
    echo "Ollama:     $(echo "$ollama_result" | jq '.tok_per_sec') tok/s"
    echo "llama.cpp:  $(echo "$llama_cpp_result" | jq '.tok_per_sec') tok/s"
    echo "SPEEDUP:    $speedup x"
    echo ""

    # Valutazione
    if [[ $(echo "$speedup >= 2.0" | bc) -eq 1 ]]; then
        log_success "Speedup raggiunto: $speedup x (obiettivo: 2-4x)"
    else
        log_warning "Speedup inferiore alle aspettative: $speedup x (obiettivo: 2-4x)"
        log_info "Possibili cause:"
        log_info "  - Servizi non completamente avviati"
        log_info "  - Configurazione non ottimizzata"
        log_info "  - Problemi di connessione o porte"
        log_info "  - Modello non disponibile su una delle piattaforme"
    fi

    # Output dettagliato per logging
    echo ""
    echo "=== DETTAGLI TECNICI ==="
    echo "Ollama risultato: $ollama_result"
    echo "llama.cpp risultato: $llama_cpp_result"
}

# Esegui main con tutti gli argomenti
main "$@"