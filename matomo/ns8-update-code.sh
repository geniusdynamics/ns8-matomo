#!/bin/sh
#
# Copyright (C) 2026 Nethesis S.r.l.
# SPDX-License-Identifier: GPL-3.0-or-later
#
# NS8 addition: the Matomo code lives in volumes that are filled from
# /usr/src/matomo only on the first start. Copy a newer Matomo release of the
# image over it (config.ini.php, the module's common.config.ini.php,
# third-party plugins and the data directories are kept) and update the
# plugins bundled with the image (LoginLdap). An installation that is already
# newer, e.g. updated with Matomo's own updater, is left alone.
set -e

version() {
	sed -n "s/.*const VERSION = '\([^']*\)'.*/\1/p" "$1/core/Version.php" 2>/dev/null
}

newer() { # $1 > $2
	php -r 'exit(version_compare($argv[1], $argv[2], ">") ? 0 : 1);' "$1" "$2"
}

plugin_version() {
	sed -n 's/^ *"version": *"\([^"]*\)".*/\1/p' "$1/plugin.json" 2>/dev/null | head -n 1
}

cd /var/www/html
image=$(version /usr/src/matomo)
current=$(version .)
if [ -n "$image" ] && { [ -z "$current" ] || newer "$image" "$current"; }; then
	echo "ns8-update-code: Matomo ${current:-?} -> ${image}" >&2
	tar cf - --one-file-system -C /usr/src/matomo \
		--exclude=./config/config.ini.php \
		--exclude=./config/common.config.ini.php \
		--exclude=./tmp \
		--exclude=./misc/user \
		. | tar xf - --no-overwrite-dir
	# config/common.config.ini.php is a read-only mount of the module
	find . -path ./config/common.config.ini.php -prune -o -exec chown www-data:www-data {} +
fi

for dir in /usr/src/matomo/plugins/LoginLdap; do
	name=$(basename "$dir")
	if [ "$(plugin_version "$dir")" != "$(plugin_version "plugins/$name")" ]; then
		echo "ns8-update-code: plugin $name $(plugin_version "plugins/$name") -> $(plugin_version "$dir")" >&2
		rm -rf "plugins/$name"
		cp -a "$dir" "plugins/$name"
		chown -R www-data:www-data "plugins/$name"
	fi
done
