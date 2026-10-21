# ns8-matomo

This is a module for [NS8](https://github.com/NethServer/ns8-core) for the [Matomo](https://github.com/matomo-org/matomo) project.

The module is based on the official [Matomo Docker image](https://github.com/matomo-org/docker).

## Features

- PHP FPM with nginx as reverse proxy
- Redis caching
- MariaDB database

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

Assuming the Matomo instance is named `matomo1`, launch `configure-module` with the following parameters:

| Parameter      | Description                                 |
| -------------- | ------------------------------------------- |
| `host`         | Fully qualified domain name for Matomo      |
| `lets_encrypt` | Enable or disable Let's Encrypt certificate |
| `http2https`   | Enable or disable HTTP to HTTPS redirection |

Example:

```bash
api-cli run module/matomo1/configure-module --data '{"host": "matomo.example.org", "lets_encrypt": true, "http2https": true}'
```

The above command will start and configure the Matomo instance. The database
(MariaDB, database and user `matomo`) and its random passwords are created by
`create-module` and stored in `state/database.env` and `state/matomo.env`.

Open `https://matomo.example.org/` and finish the Matomo installation wizard
right away: until the first super user is created, anyone who can reach the
host name can complete the wizard.

Test the Matomo backend service from the node:

```bash
curl -H 'Host: matomo.example.org' http://127.0.0.1/
```

## Images

- `matomo-app`: built by `build-images.sh` from the official
  [matomo-org/docker](https://github.com/matomo-org/docker) build files,
  vendored in `matomo/`. The PHP base image is pinned to a release with the
  fix for CVE-2026-109618/109619 ("PHP2Shell"), because the official Matomo
  images on Docker Hub do not ship a fixed PHP yet. Once
  `docker.io/library/matomo` is rebuilt on PHP >= 8.4.27, the module can use
  it again.
- `docker.io/library/mariadb`, pinned by version and digest.

The Matomo code is kept in persistent volumes and is copied there from the
image only on the first start: a new image updates PHP and the system
libraries, while Matomo itself is updated with its built-in updater.

## Backup and restore

The database is saved as an SQL dump (`state/matomo.sql`), together with the
Matomo volumes and the environment files. Restore loads the dump into a new,
empty database volume.

## Smarthost Setting Discovery

Some configuration settings, like the smarthost setup, are not part of the `configure-module` action input: they are discovered by looking at some Redis keys. To ensure the module is always up-to-date with the centralized [smarthost setup](https://geniusdynamics.github.io/ns8-core/core/smarthost/) every time Matomo starts, the command `bin/discover-smarthost` runs and refreshes the `state/smarthost.env` file with fresh values from Redis.

Furthermore if smarthost setup is changed when Matomo is already running, the event handler `events/smarthost-changed/10reload_services` restarts the main module service.

See also the `systemd/user/matomo.service` file.

This setting discovery is just an example to understand how the module is expected to work: it can be rewritten or discarded completely.

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

