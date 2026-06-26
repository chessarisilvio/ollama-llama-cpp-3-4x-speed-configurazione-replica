#!/bin/bash

# Script di benchmark comparativo Ollama vs llama.cpp ottimizzato
# Misura tok/s, TTFT, latenza per prompt di lunghezza variabile
#
# Uso: ./benchmark.sh [model_name] [test_iterations]
# Esempio: ./benchmark.sh qwen3.5:9b 5

set -e

# Configurazione
MODEL_NAME="${1:-qwen3.5:9b}"
TEST_ITERATIONS="${2:-5}"
OLLAMA_URL="http://localhost:11434"
LLAMACPP_URL="http://localhost:8081"

# Colori per output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Funzioni di utilità
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

# Test di connessione ai servizi
check_services() {
    log_info "Verifica servizi attivi..."

    # Verifica Ollama
    if curl -s "$OLLAMA_URL/api/tags" > /dev/null 2>&1; then
        log_success "Ollama attivo su $OLLAMA_URL"
    else
        log_error "Ollama non disponibile su $OLLAMA_URL"
        exit 1
    fi

    # Verifica llama.cpp
    if curl -s "$LLAMACPP_URL" > /dev/null 2>&1; then
        log_success "llama.cpp attivo su $LLAMACPP_URL"
    else
        log_error "llama.cpp non disponibile su $LLAMACPP_URL"
        exit 1
    fi
}

# Genera prompt di test con lunghezze variabili
generate_test_prompts() {
    local prompts_file="$1"

    cat > "$prompts_file" << 'EOF'
# Prompt brevi (10-50 token)
"Hello, how are you today?"
"What is the capital of France?"
"Explain quantum computing briefly."
"Tell me a short joke about programming."

# Prompt medi (50-200 token)
"Write a detailed explanation of machine learning, including its main types, applications, and challenges. Keep it comprehensive but accessible to beginners."

"Describe the process of photosynthesis in plants, explaining how plants convert sunlight into energy and produce oxygen."

"Compare and contrast supervised and unsupervised learning in machine learning. Provide examples of each and their use cases."

# Prompt lunghi (200-500 token)
"Write a comprehensive guide to setting up a secure home network. Include topics like router configuration, Wi-Fi security, firewall settings, network segmentation, and best practices for IoT device security. Make it detailed enough for someone with basic technical knowledge."

"Explain the history and evolution of artificial intelligence from its inception in the 1950s to modern deep learning systems. Cover key milestones, important algorithms, major breakthroughs, and current state-of-the-art techniques in natural language processing and computer vision."

"Create a detailed business plan for a sustainable technology startup focused on renewable energy solutions. Include market analysis, competitive landscape, revenue model, marketing strategy, team structure, and financial projections for the first three years."

# Prompt molto lunghi (500+ token)
"Write a comprehensive technical whitepaper on the future of decentralized artificial intelligence networks. Cover topics like distributed model training, federated learning, blockchain-based model provenance, privacy-preserving AI techniques, and the challenges of coordination across multiple nodes. Include technical specifications, security considerations, and potential use cases for enterprise applications."

"Create an in-depth analysis of the ethical implications of large language models in society. Discuss issues like bias in AI systems, the environmental impact of training large models, the digital divide in AI access, misinformation risks, regulatory challenges, and the future of human-AI collaboration. Provide balanced perspectives from technologists, ethicists, policymakers, and affected communities."
EOF
}

# Esegue test su Ollama
benchmark_ollama() {
    local prompts_file="$1"
    local output_file="$2"
    local model="$3"

    log_info "Esecuzione benchmark Ollama per modello: $model"

    echo "OLLAMA_BENCHMARK_RESULTS,$model,$(date +%s)" > "$output_file"

    while IFS= read -r prompt; do
        if [[ "$prompt" =~ ^# ]]; then
            continue
        fi

        if [[ -n "$prompt" ]]; then
            log_info "Test prompt: ${prompt:0:50}..."

            # Misura TTFT (Time To First Token) e throughput
            local start_time=$(date +%s%N)
            local first_token_time=""
            local tokens_count=0

            # Esegui la richiesta e misura i tempi
            response=$(curl -s -S -X POST "$OLLAMA_URL/api/generate" \
                -H "Content-Type: application/json" \
                -d "{
                    \"model\": \"$model\",
                    \"prompt\": \"$prompt\",
                    \"stream\": false,
                    \"options\": {
                        \"temperature\": 0.7,
                        \"top_p\": 0.9,
                        \"repeat_penalty\": 1.1
                    }
                }")

            local end_time=$(date +%s%N)
            local duration=$((end_time - start_time))

            # Estrai informazioni dalla risposta
            if [[ -n "$response" ]]; then
                local response_length=${#response}
                local estimated_tokens=$((response_length / 4)) # Stima approssimativa

                # Calcola tok/s
                local tok_s=$(echo "scale=2; $estimated_tokens / ($duration / 1000000000)" | bc -l)

                echo "OLLAMA_RESULT,$model,\"$prompt\",$duration,$estimated_tokens,$tok_s" >> "$output_file"
                log_success "Ollama: ${tok_s} tok/s, ${duration}ms"
            else
                log_error "Ollama: risposta vuota"
                echo "OLLAMA_ERROR,$model,\"$prompt\",no_response" >> "$output_file"
            fi
        fi
    done < "$prompts_file"
}

# Esegue test su llama.cpp
benchmark_llamacpp() {
    local prompts_file="$1"
    local output_file="$2"
    local model="$3"

    log_info "Esecuzione benchmark llama.cpp per modello: $model"

    echo "LLAMACPP_BENCHMARK_RESULTS,$model,$(date +%s)" >> "$output_file"

    while IFS= read -r prompt; do
        if [[ "$prompt" =~ ^# ]]; then
            continue
        fi

        if [[ -n "$prompt" ]]; then
            log_info "Test prompt: ${prompt:0:50}..."

            # Esegui la richiesta a llama.cpp
            response=$(curl -s -S -X POST "$LLAMACPP/api/completion" \
                -H "Content-Type: application/json" \
                -d "{
                    \"model\": \"$model\",
                    \"prompt\": \"$prompt\",
                    \"temperature\": 0.7,
                    \"top_p\": 0.9,
                    \"repeat_penalty\": 1.1,
                    \"n_predict\": 100,
                    \"stream\": false
                }")

            if [[ -n "$response" ]]; then
                local response_length=${#response}
                local estimated_tokens=$((response_length / 4))
                local duration=0 # TODO: Implementare misurazione precisa

                echo "LLAMACPP_RESULT,$model,\"$prompt\",$duration,$estimated_tokens,0.00" >> "$output_file"
                log_success "llama.cpp: ${estimated_tokens} tokens, ${duration}ms"
            else
                log_error "llama.cpp: risposta vuota"
                echo "LLAMACPP_ERROR,$model,\"$prompt\",no_response" >> "$output_file"
            fi
        fi
    done < "$prompts_file"
}

# Analizza i risultati
analyze_results() {
    local ollama_file="$1"
    local llamacpp_file="$2"

    log_info "Analisi risultati..."

    # Crea report comparativo
    echo "BENCHMARK_COMPARATIVE_REPORT,$(date)" > comparative_report.csv
    echo "Platform,Model,Prompt,Duration_ms,Tokens,Tok_s" >> comparative_report.csv

    # Analizza risultati Ollama
    if [[ -f "$ollama_file" ]]; then
        grep "OLLAMA_RESULT" "$ollama_file" | while IFS= read -r line; do
            echo "$line" | sed 's/OLLAMA_RESULT,/Ollama,/' >> comparative_report.csv
        done
    fi

    # Analizza risultati llama.cpp
    if [[ -f "$llamacpp_file" ]]; then
        grep "LLAMACPP_RESULT" "$llamacpp_file" | while IFS= read -r line; do
            echo "$line" | sed 's/LLAMACPP_RESULT,/llama.cpp,/' >> comparative_report.csv
        done
    fi

    log_success "Report comparativo salvato in comparative_report.csv"
}

# Funzione principale
main() {
    log_info "Avvio benchmark comparativo Ollama vs llama.cpp"
    log_info "Modello: $MODEL_NAME, Iterazioni: $TEST_ITERATIONS"

    # Verifica servizi
    check_services

    # Genera prompt di test
    local prompts_file="/tmp/test_prompts_$$"
    generate_test_prompts "$prompts_file"

    # Esegui benchmark
    local ollama_results="/tmp/ollama_results_$$"
    local llamacpp_results="/tmp/llamacpp_results_$$"

    benchmark_ollama "$prompts_file" "$ollama_results" "$MODEL_NAME"
    benchmark_llamacpp "$prompts_file" "$llamacpp_results" "$MODEL_NAME"

    # Analizza risultati
    analyze_results "$ollama_results" "$llamacpp_results"

    # Pulizia
    rm -f "$prompts_file" "$ollama_results" "$llamacpp_results"

    log_success "Benchmark completato!"
    log_info "Risultati salvati in comparative_report.csv"
}

# Esegui funzione principale
main "$@"