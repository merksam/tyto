#!/bin/bash
# Publishes site/ to Cloudflare Pages as the project "tyto", served at tyto.random.travel.
#
# Uploads the directory directly, so the repository never has to be connected to Cloudflare
# and can stay private if you want. random.travel's DNS is already on Cloudflare, so the
# custom domain is a CNAME Cloudflare creates for you the first time.
#
# One-time: npx wrangler login
# Then: scripts/deploy-site.sh
#
# The App Store needs both of these reachable:
#   https://tyto.random.travel/           (Support URL)
#   https://tyto.random.travel/privacy.html   (Privacy Policy URL)
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="${PROJECT:-tyto}"

cd "$ROOT"
npx wrangler pages deploy site --project-name "$PROJECT" --commit-dirty=true

cat >&2 <<'NOTE'

If this was the first deploy, add the custom domain once:
  Cloudflare dashboard > Workers & Pages > tyto > Custom domains > tyto.random.travel
The DNS record is created automatically because random.travel is already on this account.
NOTE
