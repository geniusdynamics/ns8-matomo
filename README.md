# ns8-matomo

This is a module for [NS8](https://github.com/NethServer/ns8-matomo) for the [Matomo](https://github.com/matomo-org/matomo) project.

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

### MariaDB Service Configuration

| Parameter                        | Value                               |
| -------------------------------- | ----------------------------------- |
| `MYSQL_ROOT_PASSWORD`            | Set a strong password for root user |
| `MARIADB_AUTO_UPGRADE`           | 1                                   |
| `MARIADB_DISABLE_UPGRADE_BACKUP` | 1                                   |

### Database Configuration

| Parameter                       | Description                           |
| ------------------------------- | ------------------------------------- |
| `MYSQL_PASSWORD`                | Password for the Matomo database user |
| `MYSQL_DATABASE`                | Name of the Matomo database           |
| `MYSQL_USER`                    | Username for the Matomo database      |
| `MATOMO_DATABASE_ADAPTER`       | mysql                                 |
| `MATOMO_DATABASE_TABLES_PREFIX` | Table prefix (optional)               |
| `MATOMO_DATABASE_USERNAME`      | Database username                     |
| `MATOMO_DATABASE_PASSWORD`      | Database password                     |
| `MATOMO_DATABASE_DBNAME`        | Database name                         |
| `MARIADB_INITDB_SKIP_TZINFO`    | 1                                     |

### Matomo Environment Configuration

| Parameter              | Description                                 |
| ---------------------- | ------------------------------------------- |
| `MATOMO_DATABASE_HOST` | Database host (e.g., MariaDB module)        |
| `PHP_MEMORY_LIMIT`     | PHP memory limit (e.g., 2048M)              |
| `host`                 | Fully qualified domain name for Matomo      |
| `http2https`           | Enable or disable HTTP to HTTPS redirection |
| `lets_encrypt`         | Enable or disable Let's Encrypt certificate |

Example:

```bash
api-cli run module/matomo1/configure-module --data '{}'
```

The above command will start and configure the Matomo instance.

Test the Matomo backend service:

```bash
curl http://127.0.0.1/matomo/
```

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

