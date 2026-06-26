# Configurazione Replicabile Ollama→llama.cpp: +3-4x Speed

Questo pacchetto contiene configurazioni pronte all'uso per ottenere un speedup di 3-4x passando da Ollama a llama.cpp ottimizzato.

## Struttura del Pacchetto

```
05-config-riplicabile/
├── README.md                           # Questo file
├── start-llama.sh                      # Script di avvio universale
├── config-p40.json                     # Configurazione ottimizzata P40
├── config-rtx3050.json                 # Configurazione ottimizzata RTX 3050
├── config-generale.json                # Configurazione base per altre GPU
├── .env.example                        # Template variabili d'ambiente
└── benchmark-comparativo.sh            # Script di benchmark rapido
```

## Prerequisiti

1. **llama-server installato**: versione con supporto MTP (Mixture of Triton Experts)
2. **Modelli GGUF**: scaricati e disponibili nei percorsi specificati
3. **GPU supportata**: NVIDIA con CUDA supportato
4. **Dipendenze**: `curl`, `bc`, `jq` (per JSON parsing)

## Configurazioni GPU

### 1. Tesla P40 (24GB VRAM) - Ideale per modelli 35B+

**File**: `config-p40.json`

```json
{
  "model": "Qwen3.6-35B-A3B-UD-Q4_K_XL.gguf",
  "port": 8090,
  "ngl": 99,
  "flash_attn": "on",
  "cache_type_k": "kvarn4",
  "cache_type_v": "kvarn4",
  "ctx_size": 65536,
  "threads": 6,
  "parallel": 1,
  "no_warmup": true,
  "metrics": true,
  "jinja": true,
  "fit": "off",
  "reasoning_budget": 1024
}
```

**Performance attese**: 3-4x speedup vs Ollama default

### 2. RTX 3050 (8GB VRAM) - Ideale per modelli 9B

**File**: `config-rtx3050.json`

```json
{
  "model": "Qwen3.5-9B-Q5_K_M.gguf",
  "port": 8081,
  "ngl": 999,
  "flash_attn": "auto",
  "cache_type_k": "kvarn4",
  "cache_type_v": "kvarn4",
  "ctx_size": 32768,
  "threads": 6,
  "parallel": 1,
  "no_warmup": true,
  "metrics": true,
  "jinja": true,
  "fit": "off"
}
```

**Performance attese**: 2-3x speedup vs Ollama default

### 3. Configurazione Generale (Adattabile)

**File**: `config-generale.json`

Configurazione di base che può essere adattata per altre GPU modificando i parametri chiave:

- `ngl`: Numero di layer da offloadare (99 = tutti, 999 = automatico)
- `flash_attn`: "on", "auto", o "off"
- `ctx_size`: Dimensione contesto in token
- `threads`: Numero di thread CPU (consigliato: numero core fisici)

## Utilizzo

### Avvio con Script Universale

```bash
# Copia e modifica lo script per la tua configurazione
cp start-llama.sh ~/start-llama-custom.sh
nano ~/start-llama-custom.sh

# Rendi eseguibile
chmod +x ~/start-llama-custom.sh

# Avvia il servizio
~/start-llama-custom.sh
```

### Avvio Diretto con JSON

```bash
# Per P40
llama-server -m ./models/Qwen3.6-35B-A3B-UD-Q4_K_XL.gguf \
  -c 65536 \
  -ngl 99 \
  --flash-attn=on \
  --cache-type-k=kvarn4 \
  --cache-type-v=kvarn4 \
  --threads 6 \
  --no-warmup \
  --metrics \
  --jinja \
  --parallel 1 \
  --fit off \
  -p 8090

# Per RTX 3050
llama-server -m ./models/Qwen3.5-9B-Q5_K_M.gguf \
  -c 32768 \
  -ngl 999 \
  --flash-attn=auto \
  --cache-type-k=kvarn4 \
  --cache-type-v=kvarn4 \
  --threads 6 \
  --no-warmup \
  --metrics \
  --jinja \
  --parallel 1 \
  --fit off \
  -p 8081
```

### Variabili d'Ambiente

Copia `.env.example` in `.env` e personalizza:

```bash
cp .env.example .env
nano .env
```

```bash
# Esempio .env
MODEL_PATH="./models"
LOG_LEVEL="info"
METRICS_PORT="8091"
```

## Benchmark Rapido

Esegui il benchmark per validare il speedup:

```bash
./benchmark-comparativo.sh
```

Output atteso:
```
=== BENCHMARK COMPARATIVO ===
Ollama: 15.2 tok/s
llama.cpp: 48.7 tok/s
SPEEDUP: 3.2x
```

## Ottimizzazioni Chiave

### Flag Responsabili del Speedup

| Flag | Impatto | Descrizione |
|------|---------|-------------|
| `-ngl 99` | ⭐⭐⭐⭐⭐ | Offload completo GPU |
| `--flash-attn=on` | ⭐⭐⭐⭐⭐ | Flash Attention v2 |
| `--cache-type-k=kvarn4` | ⭐⭐⭐⭐ | Cache KV 4-bit |
| `--ctx-size=65536` | ⭐⭐⭐ | Contesto esteso |
| `--threads=6` | ⭐⭐⭐ | Thread CPU ottimizzati |
| `--no-warmup` | ⭐ | No warmup iniziale |

### Adattamento per Modelli Diversi

#### Modelli più piccoli (7B-13B)
- Riduci `ctx_size` a 32768 o 16384
- `ngl` può essere ridotto a 50-80 se VRAM limitata
- Flash Attention sempre abilitato se supportato

#### Modelli più grandi (70B+)
- Aumenta `ctx_size` solo se VRAM sufficiente
- Usa `flash-attn=auto` per compatibilità
- Monitora l'uso di VRAM con `--metrics`

## Debug e Monitoraggio

### Metriche Prometheus

Abilita con `--metrics` e accedi a:
```
http://localhost:8090/metrics
```

### Log di Debug

```bash
# Attiva debug dettagliato
llama-server [flags] --log-level debug
```

### Monitoraggio VRAM

```bash
# Monitoraggio in tempo reale
watch -n 1 nvidia-smi
```

## Note Importanti

1. **Compatibilità**: Le configurazioni sono testate con Qwen3.5/3.6, ma applicabili ad altri modelli GGUF
2. **VRAM Usage**: Monitorare sempre l'uso di VRAM, specialmente con contesti grandi
3. **Flash Attention**: Disabilitare se la GPU non lo supporta (vecchie GPU)
4. **Thread Count**: Impostare al numero di core fisici per ottimizzazione CPU
5. **Porte**: Usare porte diverse per istanze multiple

## Troubleshooting

### Problemi comuni

1. **"CUDA out of memory"**: Ridurre `ctx_size` o `ngl`
2. **"Flash Attention not supported"**: Usare `--flash-attn=auto` o `off`
3. **"High latency"**: Verificare `--no-warmup` e `--parallel=1`
4. **"Low throughput"**: Controllare che `-ngl` sia impostato correttamente

### Supporto

Per problemi specifici, consultare la documentazione di llama.cpp e verificare la compatibilità della GPU.