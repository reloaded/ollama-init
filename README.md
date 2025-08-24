# ollama-init
Creates/rebuilds Ollama models from Modelfiles located in a git repository.

## Volumes
- Mount a small writable state dir at `/state` to persist checksums.

## Env
- `OLLAMA_URL`  (default: `http://ollama:11434`)
- `STATE_FILE`  (default: `/state/model_checksums.json`)
- `GIT_URL`  (default: ``)
- `GIT_REF`  (default: `main`)

## Run
docker run --rm \
  -v ollama_init_state:/state \
  --network=host \
  ghcr.io/reloaded/ollama-init:latest
