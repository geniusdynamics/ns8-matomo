# ns8-matomo

This is a module for [NS8](https://github.com/NethServer/ns8-core) for the [Matomo](https://github.com/matomo-org/matomo) project.

The module is based on the official [Matomo Docker image](https://github.com/matomo-org/docker).

## Features

- Matomo on Apache/PHP with a MariaDB database, behind the NS8 Traefik proxy
  (visitor addresses are read from `X-Forwarded-For`, also when Matomo is
  published through the Traefik of another node)
- Emails (reports, password reset) go out through the cluster smarthost
- Installation without the public web installer: the first configuration
  creates the super user
- Login with a user domain of the cluster or an LDAP server (LoginLdap plugin),
  optionally limited to the members of a group
- New Matomo releases of the image are applied on update, including the
  database upgrade
- Reports are built hourly in the background (`matomo-archive.timer`)
- Backup and restore with an SQL dump, clone-module

## Install

Instantiate the module with:

```bash
add-module ghcr.io/geniusdynamics/matomo:latest 1
```

The output of the command will return the instance name.

Example output:

```json
{
  "module_id": "matomo1",
  "image_name": "matomo",
  "image_url": "ghcr.io/geniusdynamics/matomo:latest"
}
```

## Configure

Assuming the Matomo instance is named `matomo1`, launch `configure-module`
with the following parameters:

| Parameter          | Description                                                        |
| ------------------ | ------------------------------------------------------------------ |
| `host`             | Fully qualified domain name for Matomo                             |
| `lets_encrypt`     | Enable or disable Let's Encrypt certificate                        |
| `http2https`       | Enable or disable HTTP to HTTPS redirection                        |
| `admin_user`       | First configuration only: user name of the Matomo super user       |
| `admin_password`   | First configuration only: its password (min. 12 characters, not stored) |
| `admin_email`      | First configuration only: its email address                        |
| `site_url`         | First configuration only, optional: first website to track         |
| `ldap_enabled`     | Login with a user domain or LDAP server                            |
| `ldap_view_access` | `none` (default) or `all`: view access of a new LDAP user          |
| `ldap_*`           | Directory settings, see below                                      |

Example:

```bash
api-cli run module/matomo1/configure-module --data '{
  "host": "matomo.example.org", "lets_encrypt": true, "http2https": true,
  "admin_user": "admin", "admin_password": "a long secret password",
  "admin_email": "admin@example.org"
}'
```

The above command starts Matomo and installs it with the given super user, so
the Matomo web installer is never reachable from the network. The database
(MariaDB, database and user `matomo`) and its random passwords are created by
`create-module` and stored in `state/database.env` and `state/matomo.env`.
Without `admin_user` the web installer at `https://matomo.example.org/` has to
be finished right away: until the first super user is created, anyone who can
reach the host name can complete it.

Test the Matomo backend service from the node:

```bash
curl -H 'Host: matomo.example.org' http://127.0.0.1/
```

### Login with a user domain or LDAP server

With `ldap_enabled` the [LoginLdap](https://plugins.matomo.org/LoginLdap)
plugin is activated. Users log in with their directory account; Matomo creates
the user on the first login. Local Matomo accounts, like the super user, keep
working.

| Parameter             | Description                                                              |
| --------------------- | ------------------------------------------------------------------------ |
| `ldap_source`         | `domain`: a user domain of the cluster (recommended); `custom`: an LDAP server |
| `ldap_domain`         | `domain`: name of the user domain                                        |
| `ldap_group`          | Optional: only members of this group (nested groups count). Active Directory only |
| `ldap_url`            | `custom`: `ldaps://host:636` or `ldap://host:389`                        |
| `ldap_start_tls`      | `custom`: StartTLS for `ldap://`                                         |
| `ldap_tls_verify`     | `custom`: verify the server certificate (default true)                   |
| `ldap_schema`         | `custom`: `ad` or `rfc2307`                                              |
| `ldap_base_dn`, `ldap_bind_dn`, `ldap_bind_password` | `custom`: search base and service account |
| `ldap_user_attribute` | `custom`, optional: login attribute (default `sAMAccountName` or `uid`)  |

Example with a user domain:

```bash
api-cli run module/matomo1/configure-module --data '{
  "host": "matomo.example.org", "lets_encrypt": true, "http2https": true,
  "ldap_enabled": true, "ldap_view_access": "none",
  "ldap_source": "domain", "ldap_domain": "ad.example.org", "ldap_group": "matomo-users"
}'
```

A user domain is reached through the node's ldapproxy (the matomo pod uses
slirp4netns with `allow_host_loopback`); its bind account is read at every
start and after the event `user-domain-changed`. The bind password of an LDAP
server of its own is kept in `state/passwords.env`, never in the module
environment. The module writes the LoginLdap settings to
`config/common.config.ini.php` (generated at every start, not part of the
backup); settings changed in the Matomo UI are stored in `config.ini.php` and
take precedence.

## Images

- `matomo-app`: built by `build-images.sh` from the official
  [matomo-org/docker](https://github.com/matomo-org/docker) build files,
  vendored in `matomo/`. The PHP base image is pinned to a release with the
  fix for CVE-2026-109618/109619 ("PHP2Shell"), PHP 8.4.27. Once the official
  `docker.io/library/matomo` image of the vendored Matomo release is on
  Docker Hub, the module can use it again.
- `docker.io/library/mariadb`, pinned by version and digest.

The Matomo code is kept in persistent volumes. On every start the container
copies a newer Matomo release of the image into them (`matomo/ns8-update-code.sh`;
`config.ini.php`, third-party plugins and data are kept) and `bin/matomo-sync`
runs the database upgrade. An installation updated with Matomo's own updater
to a newer release than the image is left alone.

## Backup and restore

The database is saved as an SQL dump (`state/matomo.sql`), together with the
Matomo volumes, the environment files and `state/passwords.env`. Restore loads
the dump into a new, empty database volume and configures the Traefik route
and the directory login again.

## Email and smarthost

Matomo sends its emails through the cluster [smarthost](https://geniusdynamics.github.io/ns8-core/core/smarthost/).
The smarthost settings are not part of the `configure-module` input: every
time Matomo starts, `bin/discover-smarthost` reads them from Redis into
`state/smarthost.env`, and `bin/matomo-config` writes them to the `[mail]`
section of `config/common.config.ini.php`. While the smarthost is off there is
no `[mail]` section and Matomo cannot send emails. When the smarthost changes,
`events/smarthost-changed/10reload_services` restarts Matomo, which writes the
settings again.

- Encryption follows the cluster setting (`none`, STARTTLS or TLS); `none` also
  stops Matomo from switching to STARTTLS on its own.
- The certificate of the mail server is checked only when the cluster asks for
  it (`tls_verify`). A smarthost found automatically is the VPN address of the
  mail server, and its certificate names the host, so the name check could not
  pass for it.
- The sender is `noreply@` the domain of the Matomo host name
  (`matomo.example.org` sends as `noreply@example.org`).
- Mail settings and the sender changed in the Matomo UI are stored in
  `config.ini.php` and take precedence over the generated ones.
- Test the delivery with
  `runagent -m matomo1 podman exec -u www-data matomo-app ./console core:test-email you@example.org`.

## Visitor address behind a gateway node

A Matomo instance on a worker node is often published through the Traefik of
another node (a route to the worker's VPN address). The worker's Traefik then
appends the gateway's VPN address to `X-Forwarded-For`, and Matomo, which
reads the last address of the list, would record every visit with it. The
module therefore lists the cluster VPN network (`cluster/network`) in
`proxy_ips[]`, so Matomo skips it. A gateway that reaches the node through
another address, e.g. its LAN address, has to be added to `proxy_ips[]` in the
Matomo configuration.

## Update

You can forcefully update the module

```bash
api-cli run update-module --data '{"module_url":"ghcr.io/geniusdynamics/matomo:latest","instances":["matomo1"],"force":true}'
```

## Uninstall

To uninstall the instance:

```bash
remove-module --no-preserve matomo1
```

## Testing

Test the module using the `test-module.sh` script:

```bash
./test-module.sh <NODE_ADDR> ghcr.io/geniusdynamics/matomo:latest
```

The tests are made using [Robot Framework](https://robotframework.org/).

## UI Translation

Translated with [Weblate](https://hosted.weblate.org/projects/ns8/).

To setup the translation process:

1. Add [GitHub Weblate app](https://docs.weblate.org/en/latest/admin/continuous.html#github-setup) to your repository
2. Add your repository to [hosted.weblate.org](https://hosted.weblate.org) or ask a NethServer developer to add it to the NS8 Weblate project

