#!/bin/sh
# Reapplies the declarative half of the instance on every start, so rotating a podman
# secret needs only a restart. Changes made in the web admin UI to these keys are lost.
set -eu

occ() { php /var/www/html/occ "$@"; }
present() { occ app:getpath "$1" >/dev/null 2>&1; }

# An unreachable app store must not keep the site down; the next start retries.
for app in notify_push richdocuments spreed; do
    present "$app" || occ app:install "$app" || echo "WARNING: $app not installed"
done

occ background:cron

if present notify_push; then
    occ config:app:set notify_push base_endpoint --value="${OVERWRITECLIURL}/push"
fi

if present richdocuments; then
    occ config:app:set richdocuments wopi_url --value="https://${COLLABORA_HOST}"
fi

# Both deletes exit 0 when there is nothing to remove, which is what makes the
# add idempotent and lets a rotated secret take effect.
if present spreed; then
    occ talk:signaling:delete "https://${TALK_HOST}"
    occ talk:signaling:add --verify "https://${TALK_HOST}" "$SIGNALING_SECRET"
    occ talk:turn:delete turn "${TALK_HOST}:${TALK_PORT}" udp,tcp
    occ talk:turn:add --secret "$TURN_SECRET" turn "${TALK_HOST}:${TALK_PORT}" udp,tcp
fi
