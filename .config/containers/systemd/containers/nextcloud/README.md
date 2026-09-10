# Nextcloud on maxq

Rootless podman quadlets, everything as `cuyler`. Units live here, config in
`~/.config/containers/config/nextcloud/`, data under
`/media/raid-ssd-01/containers/nextcloud/`.

| Unit | Image | Role |
| --- | --- | --- |
| `nextcloud-postgres` | `postgres:18` | database, `db/18/docker` |
| `nextcloud-redis` | `redis:7-alpine` | cache, locking, sessions |
| `nextcloud-app` | `nextcloud:34-fpm` | php-fpm, uid 33 |
| `nextcloud-nginx` | `nginx-unprivileged` | front end, Traefik target |
| `nextcloud-cron` | `nextcloud:34-fpm` | `cron.php` every 300s |
| `nextcloud-notify-push` | `nextcloud:34-fpm` | client push |
| `nextcloud-imaginary` | `aio-imaginary` | previews, port 9001 |
| `nextcloud-collabora` | `collabora/code` | office, `office.ohmstead.ca` |
| `nextcloud-talk` | `aio-talk` | signaling, TURN, `talk.ohmstead.ca` |

The app set, cron mode, push endpoint, Collabora WOPI URL and the Talk signaling
and TURN wiring are reapplied by `hooks/before-starting/20-converge.sh` on every
start; index and primary-key migrations by `hooks/post-upgrade/`. So rotating a
podman secret needs nothing but `systemctl --user restart nextcloud-app`, and
anything those hooks set must be changed there rather than in the web admin UI or
with `occ`, which they overwrite on the next start.

## One-time setup

DNS at Porkbun, same account as `traefik-porkbun-dns-api-key`:

    cloud.ohmstead.ca   A -> maxq
    office.ohmstead.ca  A -> maxq
    talk.ohmstead.ca    A -> maxq

- Router: forward 3478/tcp and 3478/udp to maxq.
- `loginctl enable-linger cuyler`
- btrfs, before the first start: `mkdir -p /media/raid-ssd-01/containers/nextcloud/db && chattr +C /media/raid-ssd-01/containers/nextcloud/db`
- `AutoUpdate=registry` does nothing unless `podman-auto-update.timer` is enabled
  for the user. Collabora, aio-talk and aio-imaginary are pinned, so only
  nextcloud, postgres, redis and nginx would float.

Secrets, using the real Migadu password for the SMTP one:

    for s in nextcloud-postgres-password nextcloud-admin-password \
             nextcloud-smtp-password collabora-admin-password \
             nextcloud-talk-turn-secret nextcloud-talk-signaling-secret \
             nextcloud-talk-internal-secret; do
        openssl rand -base64 36 | tr -d '\n' | podman secret create "$s" -
    done

## Deploy

    systemctl --user daemon-reload
    systemctl --user start nextcloud-postgres nextcloud-redis
    systemctl --user start nextcloud-app nextcloud-nginx nextcloud-cron
    journalctl --user -u nextcloud-app -f

The first run must log `Installing with PostgreSQL database`, then `=> dbtype is
pgsql`, then the hook output. Anything else is a failed install, see
troubleshooting. Then the rest:

    systemctl --user start nextcloud-notify-push nextcloud-imaginary \
                           nextcloud-collabora nextcloud-talk
    podman ps --format '{{.Names}}\t{{.Status}}' | grep nextcloud

## Still manual

Collabora's config is fetched from a running Collabora, so it cannot be a hook:

    podman exec -u 33 nextcloud-app php occ richdocuments:activate-config

Occasionally, and never at start because it is slow:

    podman exec -u 33 nextcloud-app php occ maintenance:repair --include-expensive

Checks no hook can make:

- `https://cloud.ohmstead.ca/settings/admin/overview` reports zero warnings
- `podman exec -u 33 nextcloud-app php occ notify_push:self-test`
- `curl -s https://talk.ohmstead.ca/api/v1/welcome`, and `nc -zv` plus `nc -zuv`
  on `talk.ohmstead.ca 3478` from off-LAN
- one document open in two browsers, edits converge
- a two-participant call with one participant off-LAN, the only test that
  exercises TURN
- a >1GB upload, which proves Traefik readTimeout, nginx body size and the PHP
  limits together:
  `curl -u admin -T bigfile.bin https://cloud.ohmstead.ca/remote.php/dav/files/admin/bigfile.bin`
- reboot maxq and confirm everything returns on its own

Client IPs must be real, not Traefik's:
`podman exec nextcloud-nginx tail -5 /var/log/nginx/access.log`. If they are
10.89.x.x, correct `set_real_ip_from` in `nginx.conf` and `trusted_proxies` in
`zz-nextcloud.config.php` against
`podman network inspect systemd-nextcloud --format '{{range .Subnets}}{{.Subnet}}{{end}}'`.
The subnet is not declared in `nextcloud.network`, so podman may pick a different
one after a rebuild.

Logs reach Loki with no Alloy change:
`{source_name="podman", container_name=~"nextcloud.*"}`.

## Backup

The database and the files must come from the same moment. The podman secret
store is not covered here and cannot be rebuilt from this repo.

    podman exec -u 33 nextcloud-app php occ maintenance:mode --on
    podman exec nextcloud-postgres pg_dump -U nextcloud nextcloud \
      > /media/raid-ssd-01/backups/nextcloud/nextcloud-$(date +%Y%m%d).sql
    # snapshot or copy html/ and data/ here
    podman exec -u 33 nextcloud-app php occ maintenance:mode --off

## Troubleshooting

- `FATAL: dbtype is ...`: the unattended install never happened. Reinstall from
  scratch. To bring the site up anyway, comment out the `before-starting` mount
  in `nextcloud-app.container`.
- `Next step: Access your instance to finish the web-based installation!`: the
  entrypoint could not install unattended, and a missing
  `NEXTCLOUD_ADMIN_PASSWORD` alone is enough to cause it because the database
  choice is nested inside the credential check. Do not open the site, the browser
  form installs SQLite into `html/data`.
- `Installing with PostgreSQL database` then instant failure: `html/config/` is
  owned by uid 100000 because podman created it for the bind-mounted config file.
  `podman unshare rm -rf /media/raid-ssd-01/containers/nextcloud/html/config`. The
  `ExecStartPre` mkdir prevents it.
- `cannot create /usr/local/etc/php/conf.d/...`: uid 33 cannot write the image's
  root-owned PHP config dir. This is why `REDIS_HOST` is unset and Redis is
  declared in `zz-nextcloud.config.php` and `php-nextcloud.ini` instead.
- `nextcloud-nginx` stuck in `starting`: its healthcheck proxies to php-fpm, so
  `nextcloud-app` is not up. `journalctl --user -u nextcloud-app -n 40`.
- `nextcloud-talk` unhealthy: the image healthcheck covers signaling 8081, janus
  8188, nats 4222, coturn 3478 and `/api/v1/stats`. `Could not initialize janus
  MCU ... will retry` in the first seconds is normal, and a problem only if
  `Connected to Janus WebRTC Server` never follows. Harmless: `libcurl not
  available`, `libogg not available`, `file-ondemand-sample`,
  `janus.transport.pfunix`. `supervisorctl` does not exist in this image.
- Collabora `chroot() failed (EPERM)`: known rootless regression, drop back a tag
  (`24.04.5.1.1` was the last confirmed good one).

Reinstall from scratch, destroying all Nextcloud data. Postgres must be empty or
the install refuses, and `html/` must be wiped between attempts because
`version.php` is written before the install runs, so a second start skips
installation and looks identical to the first failure.

    systemctl --user stop nextcloud-cron nextcloud-nginx nextcloud-app
    systemctl --user reset-failed nextcloud-app
    podman unshare rm -rf /media/raid-ssd-01/containers/nextcloud/html
    rm -rf /media/raid-ssd-01/containers/nextcloud/data/{*,.[!.]*}
    podman exec nextcloud-postgres psql -U nextcloud -d postgres \
      -c 'drop database nextcloud' -c 'create database nextcloud owner nextcloud'
    systemctl --user start nextcloud-app
    journalctl --user -u nextcloud-app -f

Lint config before restarting:

    podman run --rm -i --entrypoint sh docker.io/library/nextcloud:34-fpm \
      -c 'cat > /tmp/c.php && php -l /tmp/c.php' \
      < ~/.config/containers/config/nextcloud/zz-nextcloud.config.php

    podman run --rm -i --entrypoint sh docker.io/library/nextcloud:34-fpm \
      -c 'cat > /usr/local/etc/php-fpm.d/zz.conf && php-fpm -t' \
      < ~/.config/containers/config/nextcloud/php-fpm-nextcloud.conf

    podman run --rm -i --user 0 --entrypoint sh docker.io/nginxinc/nginx-unprivileged:1.29-alpine \
      -c 'cat > /etc/nginx/nginx.conf && nginx -t' \
      < ~/.config/containers/config/nextcloud/nginx.conf

    /usr/lib/podman/quadlet -dryrun -user 2>/dev/null | grep -A40 '^---nextcloud-app.service---'
