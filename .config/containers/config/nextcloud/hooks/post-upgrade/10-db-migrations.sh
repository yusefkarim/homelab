#!/bin/sh
# occ upgrade does not add indices or primary keys introduced by the new release.
set -eu

php /var/www/html/occ db:add-missing-indices
php /var/www/html/occ db:add-missing-primary-keys
