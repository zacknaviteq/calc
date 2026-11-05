#!/usr/bin/env bash
# Posts the hardening summary to Slack and uploads the reports into its thread.
#   slack-post.sh <summary-text-file> <file> [<file> ...]
# Env: SLACK_BOT_TOKEN (chat:write, files:write), SLACK_CHANNEL_ID.
# Uses files.getUploadURLExternal + files.completeUploadExternal (files.upload is retired).
set -euo pipefail
: "${SLACK_BOT_TOKEN:?}" "${SLACK_CHANNEL_ID:?}"
SUMMARY=$1; shift
API=https://slack.com/api

call() { # method json-body
  local resp
  resp=$(curl -fsS -X POST "$API/$1" -H "Authorization: Bearer $SLACK_BOT_TOKEN" \
    -H 'Content-Type: application/json; charset=utf-8' --data "$2")
  if [ "$(jq -r .ok <<<"$resp")" != "true" ]; then
    echo "::error::Slack $1 failed: $(jq -r '.error // .' <<<"$resp")" >&2
    return 1
  fi
  printf '%s' "$resp"
}

msg=$(jq -n --arg c "$SLACK_CHANNEL_ID" --rawfile t "$SUMMARY" '{channel:$c, text:$t, unfurl_links:false, unfurl_media:false}')
ts=$(call chat.postMessage "$msg" | jq -r .ts)
echo "Posted summary (ts=$ts)"

files='[]'
for f in "$@"; do
  [ -f "$f" ] || { echo "::warning::missing $f, skipped"; continue; }
  name=$(basename "$f"); len=$(stat -c %s "$f")
  up=$(curl -fsS -X POST "$API/files.getUploadURLExternal" -H "Authorization: Bearer $SLACK_BOT_TOKEN" \
    --data-urlencode "filename=$name" --data-urlencode "length=$len")
  [ "$(jq -r .ok <<<"$up")" = "true" ] || { echo "::error::getUploadURLExternal($name): $(jq -r .error <<<"$up")" >&2; exit 1; }
  curl -fsS -X POST "$(jq -r .upload_url <<<"$up")" -F "file=@$f" >/dev/null
  files=$(jq -c --arg id "$(jq -r .file_id <<<"$up")" --arg t "$name" '. + [{id:$id, title:$t}]' <<<"$files")
  echo "Uploaded $name ($len bytes)"
done

if [ "$files" != '[]' ]; then
  body=$(jq -n --argjson f "$files" --arg c "$SLACK_CHANNEL_ID" --arg ts "$ts" \
    '{files:$f, channel_id:$c, thread_ts:$ts, initial_comment:"Full reports and evidence"}')
  call files.completeUploadExternal "$body" >/dev/null
  echo "Shared $(jq length <<<"$files") files in thread"
fi
