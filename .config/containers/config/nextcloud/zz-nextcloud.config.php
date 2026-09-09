<?php
/**
 * Declarative Nextcloud configuration, version controlled and mounted
 * read-only into /var/www/html/config/.
 *
 * Nothing secret belongs in this file. Database, Redis and admin credentials
 * are written into the generated config.php from podman secrets by the image
 * entrypoint.
 */
$CONFIG = array (
  // APCu for local cache, Redis for the distributed cache and for
  // transactional file locking. Locking on Redis is what prevents concurrent
  // sync clients from corrupting files.
  'memcache.local'       => '\OC\Memcache\APCu',
  'memcache.distributed' => '\OC\Memcache\Redis',
  'memcache.locking'     => '\OC\Memcache\Redis',
  // The image only writes redis.config.php when REDIS_HOST is set, and that
  // env var also triggers a write into a directory www-data cannot touch, so
  // the connection is declared here instead. Pod loopback, no password.
  'redis' => array (
    'host' => 'localhost',
    'port' => 6379,
  ),

  // Traefik, plus pod loopback for the notify_push self-test. Verify the
  // subnet with: podman network inspect systemd-nextcloud
  'trusted_proxies'      => ['127.0.0.1', '10.89.0.0/16'],

  'default_phone_region' => 'CA',

  // errorlog sends the application log to stderr, which is where Grafana
  // Alloy picks it up and ships it to Loki with no Alloy config change.
  // loglevel 2 (WARN) is also the level the hardening guide expects.
  'log_type'             => 'errorlog',
  'loglevel'             => 2,
  'debug'                => false,

  // Run the heavy nightly jobs at 04:00 UTC
  'maintenance_window_start' => 4,

  'preview_imaginary_url'    => 'http://localhost:9001',
  'enabledPreviewProviders'  => array (
    'OC\Preview\Imaginary',
    'OC\Preview\ImaginaryPDF',
    'OC\Preview\MP3',
    'OC\Preview\TXT',
    'OC\Preview\MarkDown',
    'OC\Preview\OpenDocument',
  ),
);
