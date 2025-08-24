#!/bin/sh
set -e

: "${OLLAMA_URL:=http://ollama:11434}"
: "${MODELDIR:=/modelfiles}"
: "${STATE_FILE:=/state/model_checksums.json}"
: "${GIT_URL:=}"
: "${GIT_REF:=main}"

echo "[init] using MODELDIR=$MODELDIR OLLAMA_URL=$OLLAMA_URL STATE_FILE=$STATE_FILE GIT_URL=$GIT_URL GIT_REF=$GIT_REF"

apk add --no-cache curl jq >/dev/null

# Optional: fetch Modelfiles from Git
if [ -n "$GIT_URL" ]; then
  apk add --no-cache git >/dev/null
  rm -rf "$MODELDIR" && mkdir -p "$MODELDIR"
  git clone --depth 1 --branch "$GIT_REF" "$GIT_URL" /tmp/modelfiles_repo >/dev/null
  # Expect *.Modelfile at repo root
  cp /tmp/modelfiles_repo/modelfiles/*.Modelfile "$MODELDIR"/ 2>/dev/null || true
fi


echo "[init] waiting for ollama..."
until curl -sf "$OLLAMA_URL/api/tags" >/dev/null; do
  echo "[init] ...not up yet, retrying in 2s"
  sleep 2
done
echo "[init] ollama up."

mkdir -p "$(dirname "$STATE_FILE")"
[ -f "$STATE_FILE" ] || echo "{}" > "$STATE_FILE"
# normalize corrupted JSON
jq empty "$STATE_FILE" >/dev/null 2>&1 || echo "{}" > "$STATE_FILE"

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

	# payload from file
	mf_payload="$(jq -Rs . "$f")"

	# 1) try modelfile form
	resp="$(curl -s -w '\n%{http_code}' -X POST "$OLLAMA_URL/api/create" \
	  -H 'Content-Type: application/json' \
	  -d "{\"name\":\"$name\",\"modelfile\":$mf_payload}")"
	body="$(echo "$resp" | head -n -1)"
	code="$(echo "$resp" | tail -n1)"
	echo "[init] create(modelfile) $name -> HTTP $code $body"

	# If server complains about from/files, or non-2xx, try JSON 'from' form
	if echo "$body" | grep -qi "neither 'from' or 'files' was specified" || [ "$code" -lt 200 ] || [ "$code" -ge 300 ]; then
	  # parse the FROM line from the Modelfile
	  base="$(awk '/^[[:space:]]*FROM[[:space:]]+/ {print $2; exit}' "$f")"
	  [ -z "$base" ] && { echo "[init] ERROR: no FROM line in $f"; exit 1; }

	  # extract optional parameters we care about
	  gl="$(awk '/^[[:space:]]*PARAMETER[[:space:]]+gpu_layers[[:space:]]+/ {print $3; exit}' "$f")"
	  ctx="$(awk '/^[[:space:]]*PARAMETER[[:space:]]+num_ctx[[:space:]]+/ {print $3; exit}' "$f")"

	  params='{'
	  [ -n "$gl" ] && params="$params\"gpu_layers\": $gl"
	  [ -n "$gl" ] && [ -n "$ctx" ] && params="$params, "
	  [ -n "$ctx" ] && params="$params\"num_ctx\": $ctx"
	  params="$params}"

	  resp="$(curl -s -w '\n%{http_code}' -X POST "$OLLAMA_URL/api/create" \
		-H 'Content-Type: application/json' \
		-d "{\"name\":\"$name\",\"from\":\"$base\",\"parameters\":$params}")"
	  body="$(echo "$resp" | head -n -1)"
	  code="$(echo "$resp" | tail -n1)"
	  echo "[init] create(from) $name -> HTTP $code $body"
	  [ "$code" -ge 200 ] && [ "$code" -lt 300 ] || { echo "[init] ERROR creating $name (from-form)"; exit 1; }
	fi

  updated_state="$(echo "$updated_state" | jq --arg n "$name" --arg h "$hash" '.[$n]=$h')"
done

echo "$updated_state" > "$STATE_FILE"

if [ "$found_any" = false ]; then
  echo "[init] WARNING: no *.Modelfile files found under $MODELDIR"
fi

echo "[init] done."
