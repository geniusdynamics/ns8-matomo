#!/bin/bash

#
# Copyright (C) 2023 Nethesis S.r.l.
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Terminate on error
set -e

# Prepare variables for later use
images=()
# The image will be pushed to GitHub container registry
repobase="${REPOBASE:-ghcr.io/geniusdynamics}"
# Configure the image name
reponame="matomo"
mariadb_image="docker.io/library/mariadb:10.11.19@sha256:ab2006938ed319f467ea98b3bb6c944757c2f10b953b3038a8a8113bd81e1b75"

# Matomo application image, built from the official matomo-org/docker build
# files (vendored in matomo/) on a patched PHP base image. Exposed to the
# units as ${MATOMO_APP_IMAGE} through org.nethserver.images.
app_image="${repobase}/matomo-app:${IMAGETAG:-latest}"
echo "Build the Matomo application image..."
podman build --force-rm --pull=missing -t "${app_image}" -f matomo/Containerfile matomo/
podman tag "${app_image}" "${repobase}/matomo-app"
images+=("${repobase}/matomo-app")

# Create a new empty container image
container=$(buildah from scratch)

# Reuse existing nodebuilder-matomo container, to speed up builds
if ! buildah containers --format "{{.ContainerName}}" | grep -q nodebuilder-matomo; then
  echo "Pulling NodeJS runtime..."
  buildah from --name nodebuilder-matomo -v "${PWD}:/usr/src:Z" docker.io/library/node:24.16.0-slim@sha256:2c87ef9bd3c6a3bd4b472b4bec2ce9d16354b0c574f736c476489d09f560a203
fi

echo "Build static UI files with node..."
buildah run \
  --workingdir=/usr/src/ui \
  --env="NODE_OPTIONS=--openssl-legacy-provider" \
  nodebuilder-matomo \
  sh -c "yarn install && yarn build"

# Add imageroot directory to the container image
buildah add "${container}" imageroot /imageroot
buildah add "${container}" ui/dist /ui
# Setup the entrypoint, ask to reserve one TCP port with the label and set a rootless container
buildah config --entrypoint=/ \
  --label="org.nethserver.authorizations=traefik@node:routeadm" \
  --label="org.nethserver.tcp-ports-demand=1" \
  --label="org.nethserver.rootfull=0" \
  --label="org.nethserver.images=${app_image} ${mariadb_image}" \
  "${container}"
# Commit the image
buildah commit "${container}" "${repobase}/${reponame}"

# Append the image URL to the images array
images+=("${repobase}/${reponame}")

#
# NOTICE:
#
# It is possible to build and publish multiple images.
#
# 1. create another buildah container
# 2. add things to it and commit it
# 3. append the image url to the images array
#

#
# Setup CI when pushing to Github.
# Warning! docker::// protocol expects lowercase letters (,,)
if [[ -n "${CI}" ]]; then
  # Set output value for Github Actions
  printf "images=%s\n" "${images[*],,}" >>"${GITHUB_OUTPUT}"
else
  # Just print info for manual push
  printf "Publish the images with:\n\n"
  for image in "${images[@],,}"; do printf "  buildah push %s docker://%s:%s\n" "${image}" "${image}" "${IMAGETAG:-latest}"; done
  printf "\nThe module image refers to %s: push it with the same tag.\n" "${app_image,,}"
  printf "\n"
fi
