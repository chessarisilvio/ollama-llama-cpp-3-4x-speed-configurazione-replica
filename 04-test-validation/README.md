# Test di Validazione e Benchmark Comparativo

Questo documento descrive come eseguire benchmark comparativi tra Ollama e llama.cpp ottimizzato per validare il guadagno di performance di 3-4x.

## Panoramica

Lo script di benchmark misura e confronta le performance tra:
- **Ollama** con configurazione di default
- **llama.cpp** con configurazione ottimizzata per GPU (P40/RTX 3050)

Le metriche principali sono:
- **Token al secondo (tok/s)**: Throughput di generazione
- **Time To First Token (TTFT)**: Latenza iniziale
- **Latenza totale**: Tempo per completare la generazione
- **Scalabilità**: Performance con prompt di diverse lunghezze

## Prerequisiti

### Servizi Richiesti
1. **Ollama** in esecuzione su `localhost:11434`
2. **llama.cpp** (llama-server) in esecuzione su `localhost:8081`
3. Modelli disponibili su entrambe le piattaforme

### Dipendenze di Sistema
```bash
# Installare curl per le richieste HTTP
sudo apt update && sudo apt install -y curl

# Installare bc per calcoli matematici
sudo apt install -y bc

# Verificare servizi attivi
curl http://localhost:11434/api/tags
curl http://localhost:8081
```

## Configurazione dei Servizi

### Ollama
```bash
# Avviare Ollama (se non attivo)
ollama serve

# Verificare modelli disponibili
ollama list
```

### llama.cpp Ottimizzato
Assicurarsi che il servizio sia configurato con i flag ottimizzati:

```bash
# Configurazione P40 (35B)
llama-server -m /path/to/model.gguf \
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
  -p 8081

# Configurazione RTX 3050 (9B)
llama-server -m /path/to/model.gguf \
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
  -p 8082
```

## Esecuzione dello Script

### Utilizzo Base
```bash
# Eseguire benchmark con modello di default (qwen3.5:9b)
./benchmark.sh

# Specificare modello e iterazioni
./benchmark.sh qwen3.5:9b 10

# Testare modello 35B
./benchmark.sh qwen3.6:35b 5
```

### Parametri
- `model_name`: Nome del modello da testare (default: `qwen3.5:9b`)
- `test_iterations`: Numero di iterazioni per ogni test (default: `5`)

## Output dei Test

### File Generati
1. **`comparative_report.csv`**: Report comparativo in formato CSV
2. **File temporanei**: Rimossi automaticamente alla fine

### Struttura del Report CSV
```csv
Platform,Model,Prompt,Duration_ms,Tokens,Tok_s
Ollama,qwen3.5:9b,"Hello, how are you today?",1200,25,20.83
llama.cpp,qwen3.5:9b,"Hello, how are you today?",800,25,31.25
```

### Metriche Chiave
- **Platform**: Piattaforma testata (Ollama/llama.cpp)
- **Model**: Nome del modello
- **Prompt**: Prompt di test (troncato per brevità)
- **Duration_ms**: Durata della generazione in millisecondi
- **Tokens**: Numero di token generati
- **Tok_s**: Token al secondo (throughput)

## Analisi dei Risultati

### Metriche di Performance
1. **Throughput (tok/s)**: Metrica più importante per il guadagno di performance
2. **Latenza (TTFT)**: Tempo per il primo token
3. **Scalabilità**: Comportamento con prompt di diverse lunghezze

### Flag Ottimizzati Analizzati
| Flag | Impatto Atteso | Metrica Coinvolta |
|------|----------------|-------------------|
| `-ngl 99` | ⭐⭐⭐⭐⭐ | Throughput, Latenza |
| `--flash-attn=on` | ⭐⭐⭐⭐⭐ | Throughput (contesti lunghi) |
| `--cache-type-k=kvarn4` | ⭐⭐⭐⭐ | Throughput, VRAM usage |
| `--ctx-size=65536` | ⭐⭐⭐ | Scalabilità contesto |
| `--threads=6` | ⭐⭐⭐ | Utilizzo CPU |
| `--parallel=1` | ⭐⭐ | Latenza singola richiesta |

## Interpretazione dei Risultati

### Guadagno Atteso
- **Throughput**: 3-4x improvement con llama.cpp ottimizzato
- **Latenza**: 2-3x reduction in TTFT
- **Scalabilità**: Migliore performance con prompt lunghi grazie a Flash Attention

### Fattori di Variabilità
1. **GPU Utilizzata**: P40 (24GB) vs RTX 3050 (8GB)
2. **Dimensione Modello**: 9B vs 35B
3. **Lunghezza Prompt**: Breve (<100) vs Lungo (>500)
4. **Carico di Sistema**: Utilizzo CPU/VRAM concurrente

## Debug e Troubleshooting

### Problemi Comuni

#### Servizi Non Disponibili
```bash
# Verifica Ollama
curl http://localhost:11434/api/tags

# Verifica llama.cpp
curl http://localhost:8081

# Controlla processi
ps aux | grep -E "(ollama|llama-server)"
```

#### Errori di Connessione
- Assicurati che i servizi siano attivi prima di eseguire lo script
- Verifica porte corrette (11434 per Ollama, 8081 per llama.cpp)
- Controlla firewall locale

#### Performance Inattese
- Monitora utilizzo GPU con `nvidia-smi`
- Verifica temperature e throttling
- Controlla processi in background che potrebbero competere per risorse

### Log di Debug
Lo script include messaggi dettagliati per ogni fase:
- `[INFO]`: Messaggi informativi
- `[SUCCESS]`: Operazioni completate con successo
- `[WARNING]`: Avvertenze non critiche
- `[ERROR]`: Errori che interrompono l'esecuzione

## Best Practices

### Esecuzione dei Test
1. **Ambiente pulito**: Esegui test su sistema senza carichi concorrenti
2. **Temperature GPU**: Monitora temperature per evitare throttling
3. **Iterazioni multiple**: Usa più iterazioni per risultati statistici validi
4. **Modelli consistenti**: Testa gli stessi modelli su entrambe le piattaforme

### Analisi Comparativa
1. **Confronto diretto**: Usa gli stessi prompt per entrambe le piattaforme
2. **Metriche multiple**: Considera sia throughput che latenza
3. **Contesto reale**: Testa con prompt simili a casi d'uso reali
4. **Trend a lungo termine**: Esegui test periodici per monitorare miglioramenti

## Integrazione con CI/CD

### Script Automatizzato
```bash
#!/bin/bash
# test-benchmark-automated.sh

# Esegui benchmark completi
./benchmark.sh qwen3.5:9b 10
./benchmark.sh qwen3.6:35b 5

# Genera report
python3 generate_report.py comparative_report.csv

# Notifica risultati (opzionale)
curl -X POST "webhook-url" -d "Benchmark completati"
```

### Monitoraggio Continuo
Configura esecuzioni periodiche per monitorare:
- Degradazione delle performance
- Impatto di aggiornamenti software
- Stabilità del sistema nel tempo

## Note Tecniche

### Metriche di Performance
- **Token al secondo**: Calcolato come `tokens / (duration_seconds)`
- **TTFT**: Misurato separatamente per latenza iniziale
- **VRAM Usage**: Monitorato tramite `nvidia-smi` durante i test

### Limitazioni
- **Stima token**: Il numero di token è stimato basandosi sulla lunghezza della risposta
- **Sincronizzazione**: I test non misurano perfettamente il TTFT
- **Carico di sistema**: Altri processi possono influire sulle performance

### Future Miglioramenti
- Misurazione precisa del TTFT
- Test di carico con richieste parallele
- Analisi dettagliata dell'utilizzo VRAM
- Benchmark su dataset standardizzati