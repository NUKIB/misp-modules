# MISP Modules

Container image for [MISP modules](https://github.com/MISP/misp-modules) based on AlmaLinux 9.

This image is intended to use with [MISP](https://github.com/MISP/misp) image.

## Usage

Download the latest image:

    docker pull ghcr.io/nukib/misp-modules:latest

If you don't trust image build by GitHub Actions and stored in GitHub Container Registry or you want to build different MISP modules version, you can build this image by yourself:

    docker build --build-arg MISP_MODULES_VERSION=v2.4.165 -t ghcr.io/nukib/misp-modules https://github.com/NUKIB/misp-modules.git#main

Then you can run container from this image:

    docker run -d -p 127.0.0.0:6666:6666 ghcr.io/nukib/misp-modules:latest

### Environment variables

* `SENTRY_DSN` (optional, string) - Sentry DSN for exception logging

## License

This software is licensed under GNU General Public License version 3. MISP modules is licensed under GNU Affero General Public License version 3.

* Copyright (C) 2022-2024 [National Cyber and Information Security Agency of the Czech Republic (NÚKIB)](https://nukib.gov.cz/en/) 🇨🇿
