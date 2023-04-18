# Rootless MISP Modules

Build files for a _rootless_ container image that runs the [MISP modules](https://github.com/MISP/misp-modules).

This build is derived directly from from the excellent work of the [National Cyber and Information Security Agency of the Czech republic (NÚKIB)](https://www.nukib.cz/en/).

The resulting image is constructed from:

* Alma Linux v8 "minimal" image, as the container base image
  * (Alternative base from <docker.io/library/python:3.9-slim>)
* MISP module code from: <https://github.com/MISP/misp-modules>

This image is intended for use with the the rootless MISP container [MISP](https://github.com/MISP/misp) image and Helm chart.

## Usage

Download the latest pre-built image:

```bash
docker pull jgregmac/misp-modules:latest
```

Build from Dockerfile in GitHub, specifying misp-module tag to build from:

```bash
docker build --build-arg MISP_MODULES_VERSION=v2.4.165 \
    -t misp-modules:v2.4.165 \
    https://github.com/YaleDevSecOps/misp-modules.git#main
```

Build locally:

```bash
git clone https://github.com/YaleDevSecOps/misp-modules.git
cd misp-modules
docker build --build-arg MISP_MODULES_VERSION=v2.4.165 -t misp-modules:v2.4.165 
```

Build locally, using the alternative "docker.io/library/python:3.9-slim" base image:

```bash
git clone https://github.com/YaleDevSecOps/misp-modules.git
cd misp-modules
docker build . -f Dockerfile.3.9-slim --build-arg MISP_MODULES_VERSION=v2.4.165
```

The container can be run directly using docker for testing purposes, but it really is meant to be accessed by a running MISP instance:

```bash
docker run -d -p 127.0.0.0:6666:6666 misp-modules:latest
```

### Environment variables

* `SENTRY_DSN` (optional, string) - Sentry DSN for exception logging

### Base Image Notes

Both almalinux/8-minimal and library/python:3.9-slim produce images of similar size and with nearly identical Trivy vulnerability profiles.  AlmaLinux is the default choice here to preserve compatibility with the NÚKIB code upon which this repo is based.  However,
internally our team prefers the use of the Docker "official" Python images.  You get better control over the python version to be used
in the container image, and in general it is easier to find troubleshoot Debian-based images as the vast majority of Dockerfile examples
are based on Debian or Ubuntu base images.

## License

This software is licensed under GNU General Public License version 3. MISP modules is licensed under GNU Affero General Public License version 3.

Some portions of this repository are:

* Copyright (C) 2022 [National Cyber and Information Security Agency of the Czech republic (NÚKIB)](https://www.nukib.cz/en/)
