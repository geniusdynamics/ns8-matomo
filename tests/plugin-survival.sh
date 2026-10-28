#!/bin/sh
#
# Copyright (C) 2026 Nethesis S.r.l.
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Run in the matomo-app container (as root, working directory /var/www/html)
# by tests/matomo.robot, from tmp/ of the code volume (the /tmp of the
# container is the module's state/config, which is in the backup).
#   prepare: simulate a LoginLdap updated through the Marketplace (99.0.0), a
#            plugin the image does not bundle, and an older Matomo code in the
#            volume, so that the next start copies the code of the image
#   check:   print "ok" if both plugins survived and the code was copied
#   cleanup: restore the plugin.json of LoginLdap, remove the extra plugin
#            and this script
set -e

case "$1" in
prepare)
	cp -p plugins/LoginLdap/plugin.json tmp/robot-loginldap-plugin.json
	sed -i 's/^\( *"version": *"\)[^"]*/\199.0.0/' plugins/LoginLdap/plugin.json
	mkdir -p plugins/RobotOther
	printf '{"name": "RobotOther", "version": "1.0.0"}\n' >plugins/RobotOther/plugin.json
	sed -i "s/const VERSION = '[^']*'/const VERSION = '5.0.0'/" core/Version.php
	;;
check)
	grep -q '"version": "99.0.0"' plugins/LoginLdap/plugin.json || { echo "LoginLdap replaced"; exit 1; }
	[ -f plugins/RobotOther/plugin.json ] || { echo "RobotOther removed"; exit 1; }
	! grep -q "const VERSION = '5.0.0'" core/Version.php || { echo "code not copied"; exit 1; }
	echo ok
	;;
cleanup)
	cp -p tmp/robot-loginldap-plugin.json plugins/LoginLdap/plugin.json
	rm -rf plugins/RobotOther tmp/robot-loginldap-plugin.json "$0"
	;;
*)
	echo "usage: $0 prepare|check|cleanup" >&2
	exit 2
	;;
esac
