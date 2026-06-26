# Analisi configurazione llama.cpp ottimizzata (Silvio/P40)

Questo documento analizza la configurazione llama.cpp attualmente in uso su sistema con Tesla P40 (CUDA0) e RTX 3050 (CUDA1), così come definita nello script `llama-stack` e nel servizio systemd `llama-stack.service`.

## Overview

Il sistema esegue due istanze di `llama-server` (backend llama-mtp commit 5d246a7):
- **Modello 35B** (Qwen3.6-35B-A3B-UD-Q4_K_XL.gguf) su P40 (CUDA0) porta 8090
- **Modello 9B** (Qwen3.5-9B-Q5_K_M.gguf) su RTX 3050 (CUDA1) porta 8081 (sentinel, attualmente disattivato per liberare la RTX per Whisper GPU)

Le flag della riga di comando sono estratte dallo script `~/.local/bin/llama-stack`, funzioni `start_35b()` e `start_9b()`.

---

## Parametri per P40 (35B cervello)

| Flag | Valore | Descrizione | Impatto su throughput/latenza |
|------|--------|-------------|-------------------------------|
| `-ngl` | 99 | Numero di layer da offloadare alla GPU. 99 indica tutti i layer (il modello ha 96 layer, quindi tutti offloadati). | Massimizza l'utilizzo della GPU, riduce il carico sulla CPU, aumenta throughput. |
| `--flash-attn` | on | Abilita Flash Attention v2 (se supportato). | Riduce significativamente il tempo di calcolo dell'attenzione, migliora throughput soprattutto su lunghezze di contesto lunghe. |
| `--cache-type-k` | kvarn4 | Tipo di quantizzazione della cache chiavi (K). kvarn4 = 4-bit con gruppo di dimensione 32. | Riduce l'uso di VRAM per la cache KV, permette contesti più lunghi senza overflow. L'impatto sulla precisione è minimo per molti carichi. |
| `--cache-type-v` | kvarn4 | Stesso per i valori (V). | Stesso effetto di cui sopra. |
| `--ctx-size` | 65536 | Dimensione massima del contesto in token. | Consente di elaborare sequenze molto lunghe; aumenta l'uso di KV cache linearmente con la dimensione. Con kvarn4, 65536 token è sostenibile sulla P40 (24 GB). |
| `--reasoning-budget` | 1024 | Numero di token riservati per il pensiero (se il modello supporta reasoning). | Non influisce direttamente sul throughput di generazione standard; utile per modelli con capacità di reasoning. |
| `--threads` | 6 | Numero di thread CPU da usare per il processing non offloadato. | Corrisponde al numero di core fisici (i5-9400F: 6C/6T). Ottimizza l'uso della CPU per parti non GPU (tokenization, preprocessing). |
| `--no-warmup` | (flag) | Disabilita il warmup iniziale (esecuzione di alcuni token a vuoto). | Riduce la latenza di avvio, utile per servizi che devono rispondere rapidamente. |
| `--metrics` | (flag) | Abilita l'esportazione di metriche Prometheus. | Aggiunge un piccolo overhead di monitoraggio; trascurabile rispetto al carico di inferenza. |
| `--jinja` | (flag) | Abilita il templating Jinja per i prompt. | Necessario per modelli che usano template di chat (es. Qwen). Overhead minimo. |
| `--parallel` | 1 | Numero di richieste parallele da processare in batch. | 1 = nessun batching tra richieste; aumenta la latenza per richieste concorrenti ma migliora la latenza per richiesta singola (nessuna attesa di batch). |
| `--fit` | off | Disabilita il tentativo di adattare il modello in memoria se supera la VRAM disponibile. | Poiché il modello è già noto per entrare in VRAM, evita controlli ridondanti all'avvio. |

---

## Parametri per RTX 3050 (9B sentinel) - configurazione attuale (sentinel disattivato)

| Flag | Valore | Descrizione | Impatto su throughput/latenza |
|------|--------|-------------|-------------------------------|
| `-ngl` | 999 | Offload tutti i layer (il modello 9B ha meno layer, quindi valore alto garantisce offload completo). | Massimizza l'uso della GPU RTX 3050 (8 GB). |
| `--flash-attn` | auto | Abilita Flash Attention se supportato dalla GPU e dal modello. | Migliora throughput sull'attenzione, particolarmente utile per contesti medio-lunghi. |
| `--ctx-size` | 32768 | Dimensione contesto. | Dimezzato rispetto alla P40 per via della VRAM più limitata (8 GB). |
| `--cache-type-k` | q8_0 | Quantizzazione 8-bit per la cache chiavi. | Bilancia uso VRAM e precisione; più preciso di q4_0 ma meno di f16. |
| `--cache-type-v` | q8_0 | Stesso per i valori. | Stesso effetto. |
| `--reasoning-budget` | 128 | Token per reasoning. | Valore ridotto rispetto al 35B, adeguato al modello più piccolo. |
| `--presence-penalty` | 1.5 | Penalità di presenza (ripetizione). | Parametro di campionamento; non influisce su throughput/latenza diretto. |
| `--threads` | 2 | Thread CPU. | Ridotto rispetto alla P40 perché il modello è più piccolo e la RTX 3050 ha meno potenza di calcolo relativa. |
| `--no-mmap` | (flag) | Disabilita memory-mapping del modello file. | Carica il modello completamente in RAM/VRAM; può migliorare latenza di prima token a costo di uso memoria maggiore. |
| `--metrics` | (flag) | Abilita metriche Prometheus. | Stesso discorso di sopra. |
| `--jinja` | (flag) | Abilita templating Jinja. | Necessario per template di chat. |
| `--parallel` | 1 | Nessun batching tra richieste. | Stesso discorso di sopra. |

---

## Considerazioni sulle prestazioni

- **Throughput (token/s)**: La configurazione P40 con kvarn4 e flash-attn on raggiunge ~44 tok/s come riportato in `sistema-ai-locale.md`. La RTX 3050 con q8_0/q8_0 raggiunge ~28 tok/s (sentinel).
- **Latenza**: L'uso di `--no-warmup` e `--parallel 1` riduce la latenza di prima token e evita il batching che potrebbe aumentare la latenza per richieste singole.
- **Utilizzo VRAM**: 
  - P40: modello 35B Q4_K_XL (~22 GB) + cache KV kvarn4 per 65536 token (~2-3 GB) rimane entro i 24 GB.
  - RTX 3050: modello 9B Q5_K_M (~6 GB) + cache KV q8_0 per 32768 token (~1-2 GB) entra negli 8 GB.
- **Scalabilità**: La separazione dei modelli su due GPU permette di dedicare la P40 al carico principale (alta throughput) e la RTX 3050 a compiti secondari (es. Whisper GPU, come attualmente configurato).

---

## Note sulla replicabilità

- Questi flag sono specifici per il backend **llama-mtp** (commit 5d246a7). Altri backend (llama.cpp vanilla, BeeLLama, ik_llama) possono richiedere valori diversi o non supportare alcune opzioni (es. kvarn4 è esclusivo di alcuni fork).
- Per replicare su altre GPU, è necessario adattare:
  - `-ngl` in base al numero di layer e alla VRAM disponibile.
  - `--cache-type-*` in base alla VRAM e al contesto desiderato.
  - `--ctx-size` in base alla VRAM e al tipo di cache.
  - `--threads` in base ai core CPU disponibili.
- È consigliato avviare con `--metrics` per monitorare il throughput reale e aggiustare i parametri.

---
*File generato automaticamente nell'ambito del progetto Ollama→llama.cpp: +3-4x speed, configurazione replicabile.*