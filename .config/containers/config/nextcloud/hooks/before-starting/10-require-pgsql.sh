#!/bin/sh
# The entrypoint's database selection sits inside its admin-credential check, so one
# missing secret falls through to the browser installer, which picks SQLite and puts
# data under html/. Refusing to start keeps that wrong choice unreachable.
set -eu

dbtype=$(php -r '
    $CONFIG = [];
    @include "/var/www/html/config/config.php";
    echo $CONFIG["dbtype"] ?? "<not installed>";
')

if [ "$dbtype" != "pgsql" ]; then
    echo "FATAL: dbtype is '$dbtype', expected 'pgsql'. Refusing to start."
    echo "       Recovery: stop the app tier, clear html/ and data/, start again."
    exit 1
fi

echo "=> dbtype is $dbtype"
