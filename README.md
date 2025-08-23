# ollama-init
Creates/rebuilds Ollama models from Modelfiles.

## Volumes
- Mount your Modelfiles read-only at `/modelfiles`.
- Mount a small writable state dir at `/state` to persist checksums.

## Env
- `OLLAMA_URL`  (default: `http://ollama:11434`)
- `MODELDIR`    (default: `/modelfiles`)
- `STATE_FILE`  (default: `/state/model_checksums.json`)

## Run
docker run --rm \
  -v $PWD/modelfiles:/modelfiles:ro \
  -v ollama_init_state:/state \
  --network=host \
  ghcr.io/YOURORG/ollama-init:0.1.0
