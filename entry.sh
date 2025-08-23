#!/bin/sh
set -e

: "${OLLAMA_URL:=http://ollama:11434}"
: "${MODELDIR:=/modelfiles}"
: "${STATE_FILE:=/state/model_checksums.json}"

echo "[init] using MODELDIR=$MODELDIR OLLAMA_URL=$OLLAMA_URL STATE_FILE=$STATE_FILE"

apk add --no-cache curl jq >/dev/null

echo "[init] waiting for ollama..."
until curl -sf "$OLLAMA_URL/api/tags" >/dev/null; do
  echo "[init] ...not up yet, retrying in 2s"
  sleep 2
done
echo "[init] ollama up."

mkdir -p "$(dirname "$STATE_FILE")"
[ -f "$STATE_FILE" ] || echo "{}" > "$STATE_FILE"
# normalize corrupted JSON
if ! jq empty "$STATE_FILE" >/dev/null 2>&1; then
  echo "{}" > "$STATE_FILE"
fi

if [ ! -d "$MODELDIR" ]; then
  echo "[init] ERROR: MODELDIR $MODELDIR not mounted"; exit 1
fi

updated_state="$(cat "$STATE_FILE")"
found_any=false

for f in "$MODELDIR"/*.Modelfile; do
  [ -e "$f" ] || continue
  found_any=true
  name="$(basename "$f" .Modelfile)"
  echo "[init] processing $name from $f"

  hash="$(sha256sum "$f" | awk '{print $1}')"
  prev="$(echo "$updated_state" | jq -r --arg n "$name" '(.[$n] // "")')"

  # Check if model exists
  if curl -sf "$OLLAMA_URL/api/tags" | grep -q "\"name\":\"$name\""; then
    if [ "$hash" = "$prev" ]; then
      echo "[init] $name exists and checksum unchanged, skipping."
      continue
    else
      echo "[init] checksum changed for $name; rebuilding..."
      curl -s -X POST "$OLLAMA_URL/api/delete" \
        -H "Content-Type: application/json" \
        -d "{\"name\":\"$name\"}" >/dev/null || true
    fi
  else
    echo "[init] $name missing; creating..."
  fi

  payload="$(jq -Rs . "$f")"
  curl -s -X POST "$OLLAMA_URL/api/create" \
    -H "Content-Type: application/json" \
    -d "{\"name\":\"$name\",\"modelfile\":$payload}" >/dev/null
  echo "[init] created $name."

  updated_state="$(echo "$updated_state" | jq --arg n "$name" --arg h "$hash" '.[$n]=$h')"
done

echo "$updated_state" > "$STATE_FILE"

if [ "$found_any" = false ]; then
  echo "[init] WARNING: no *.Modelfile files found under $MODELDIR"
fi

echo "[init] done."
