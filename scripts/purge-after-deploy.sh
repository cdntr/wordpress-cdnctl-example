#!/usr/bin/env sh
# Purge the pages that change when you publish a post or ship a theme, and nothing else.
#
#   CDNTR_ACCOUNT=<account_uuid> ./scripts/purge-after-deploy.sh [theme-slug]
#
# Needs cdnctl signed in (`cdnctl login`) or CDN_ENDPOINT + CDN_ACCESS_TOKEN in the environment.
set -eu

: "${CDNTR_ACCOUNT:?set CDNTR_ACCOUNT to your CDN account uuid (cdnctl accounts ls)}"
THEME="${1:-}"

# 1. The pages whose HTML changes on every publish: exact URLs.
cdnctl purge --account "$CDNTR_ACCOUNT" \
  --paths "/,/feed/,/sitemap.xml,/wp-sitemap.xml" --type exact

# 2. A theme deploy changes CSS/JS/fonts: everything under the theme folder.
if [ -n "$THEME" ]; then
  cdnctl purge --account "$CDNTR_ACCOUNT" \
    --path "/wp-content/themes/$THEME/" --type prefix
fi
