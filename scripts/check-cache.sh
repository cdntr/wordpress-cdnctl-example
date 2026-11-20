#!/usr/bin/env sh
# Request a URL twice and print the CDN's cache verdict for each request.
#
#   ./scripts/check-cache.sh https://www.example.com/
#
# The header is X-Proxy-Cache-MT: HIT, MISS, BYPASS or EXPIRED.
set -eu
url="${1:?usage: check-cache.sh <url>}"
for i in 1 2; do
  printf 'request %s: ' "$i"
  curl -s -o /dev/null -D - "$url" | grep -i '^x-proxy-cache-mt' || echo '(no X-Proxy-Cache-MT header)'
done
