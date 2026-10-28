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
# newer, e.g. updated with Matomo's own updater, is left alone. The same holds
# for a bundled plugin: a version updated through the Matomo Marketplace is
# kept when it is newer than the one of the image. The database upgrade for
# the copied code runs afterwards (core:update in bin/matomo-sync).
set -e

# Marketplace plugins that the image adds to /usr/src/matomo/plugins
# (directory names without spaces or glob characters)
BUNDLED_PLUGINS="LoginLdap"

version() {
	sed -n "s/.*const VERSION = '\([^']*\)'.*/\1/p" "$1/core/Version.php" 2>/dev/null
}

newer() { # $1 > $2
	php -r 'exit(version_compare($argv[1], $argv[2], ">") ? 0 : 1);' "$1" "$2"
}

# Remove what a copied Matomo release no longer contains below $1 (a path
# relative to the code, e.g. core or plugins/CoreHome), as Matomo's own
# updater does (removeGoneFiles in plugins/CoreUpdater/Model.php): files and
# links to files are deleted, directories and links to directories only when
# they are empty (rmdir). Unlike Matomo's updater, the access rules that
# Matomo generates itself (.htaccess, web.config: ServerFilesGenerator) are
# kept, also when the release dropped their directory. The names are passed
# to sh as arguments, not read as lines, because a name may hold a line break.
remove_gone() {
	[ -d "$1" ] || return 0
	find "$1" -depth -mindepth 1 ! -name .htaccess ! -name web.config -exec sh -c '
		for path; do
			if [ -e "/usr/src/matomo/$path" ] || [ -L "/usr/src/matomo/$path" ]; then
				continue
			elif [ -d "$path" ]; then
				rmdir "$path" 2>/dev/null || true
			elif rm -f "$path"; then
				echo "ns8-update-code: removed $path" >&2
			else
				echo "ns8-update-code: could not remove $path" >&2
			fi
		done' sh {} +
}

is_bundled() {
	case " $BUNDLED_PLUGINS " in
	*" $1 "*) return 0 ;;
	esac
	return 1
}

# version from the plugin.json of the plugin directory $1, empty if unreadable
plugin_version() {
	php -r '$j = json_decode((string) @file_get_contents($argv[1]), true);
		echo is_array($j) && is_string($j["version"] ?? null) ? $j["version"] : "";' "$1/plugin.json"
}

cd /var/www/html
image=$(version /usr/src/matomo)
current=$(version .)
if [ -n "$image" ] && { [ -z "$current" ] || newer "$image" "$current"; }; then
	echo "ns8-update-code: Matomo ${current:-?} -> ${image}" >&2
	# the bundled plugins are handled by the loop below, which keeps a newer
	# version installed through the Marketplace
	excludes=""
	for name in $BUNDLED_PLUGINS; do
		excludes="$excludes --exclude=./plugins/$name"
	done
	# shellcheck disable=SC2086 # $excludes holds one word per option
	tar cf - --one-file-system -C /usr/src/matomo \
		--exclude=./config/config.ini.php \
		--exclude=./config/common.config.ini.php \
		--exclude=./tmp \
		--exclude=./misc/user \
		$excludes \
		. | tar xf - --no-overwrite-dir
	for dir in core libs vendor node_modules; do
		remove_gone "$dir"
	done
	for dir in /usr/src/matomo/plugins/*/; do
		name=$(basename "$dir")
		is_bundled "$name" || remove_gone "plugins/$name"
	done
	# config/common.config.ini.php is a read-only mount of the module
	find . -path ./config/common.config.ini.php -prune -o -exec chown www-data:www-data {} +
fi

for name in $BUNDLED_PLUGINS; do
	dir="/usr/src/matomo/plugins/$name"
	img=$(plugin_version "$dir")
	cur=$(plugin_version "plugins/$name")
	if [ -z "$img" ]; then
		echo "ns8-update-code: plugin $name is missing in the image" >&2
	elif [ -z "$cur" ] && [ -e "plugins/$name" ]; then
		# never replace a plugin whose version is unknown: it may be newer
		echo "ns8-update-code: plugin $name kept, its version is unreadable (image has $img)" >&2
	elif [ -z "$cur" ] || newer "$img" "$cur"; then
		echo "ns8-update-code: plugin $name ${cur:-none} -> $img" >&2
		rm -rf "plugins/$name"
		cp -a "$dir" "plugins/$name"
		chown -R www-data:www-data "plugins/$name"
	elif [ "$img" != "$cur" ]; then
		echo "ns8-update-code: plugin $name $cur kept (image has $img)" >&2
	fi
done
