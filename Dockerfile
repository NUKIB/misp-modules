# Base image with python3.9 and enabled powertools and epel repo
ARG BASE_IMAGE=docker.io/almalinux/8-minimal
# Can't use UBI as drop-in replacement.  Will need package name tuning to get the required binaries...
# ARG BASE_IMAGE=registry.access.redhat.com/ubi8/ubi
FROM $BASE_IMAGE as base

ENV \
    # Set commonly recommended environment variables for Python (do not buffer stfout/stderr)
    PYTHONUNBUFFERED=1 \
    # Suppress caching of pip install files:
    PIP_NO_CACHE_DIR=off 

RUN --mount=type=cache,target=/var/cache/dnf,sharing=locked \
    microdnf update --nodocs --setopt=install_weak_deps=0 &&\
    microdnf module enable python39 &&\
    microdnf install \
        curl findutils procps-ng python39 tar util-linux-user &&\
    alternatives --set python3 /usr/bin/python3.9 &&\
    microdnf install dnf dnf-plugins-core &&\
    dnf config-manager --set-enabled powertools &&\
    dnf remove -y --setopt protected_packages=1 dnf dnf-plugins-core
    # Classically, we would clean the DNF cache, but now we are the cache mount type to take care of this...
    # microdnf clean all &&\
    # rm -rf /var/cache/dnf

# Build stage that will build required python modules
FROM base as python-build
RUN --mount=type=cache,target=/var/cache/dnf,sharing=locked \
    microdnf install --nodocs --setopt=install_weak_deps=0 \
        gcc gcc-c++ git-core poppler-cpp-devel python39-devel python39-pip python3-virtualenv

ARG MISP_MODULES_VERSION=main
RUN --mount=type=tmpfs,target=/tmp \
    mkdir /tmp/source && cd /tmp/source && \
    git config --system http.sslVersion tlsv1.3 && \
    COMMIT=$(git ls-remote https://github.com/MISP/misp-modules.git $MISP_MODULES_VERSION | cut -f1) && \
    echo $COMMIT > /misp-modules-commit &&\
    curl --proto '=https' --tlsv1.3 --fail -sSL https://github.com/MISP/misp-modules/archive/$COMMIT.tar.gz | tar zx --strip-components=1 && \
    python3 -m venv /opt/venv &&\
    PATH="/opt/venv/bin:$PATH" &&\
    python3 -m pip install -r REQUIREMENTS

# Final image
FROM base
# Use system certificates for python requests library
ENV REQUESTS_CA_BUNDLE=/etc/ssl/certs/ca-bundle.crt

# Install system binaries needed by modules:
# (EPEL needed for "zbar" (bar code reader) package)
COPY misp-enable-epel.sh /usr/bin/
RUN --mount=type=cache,target=/var/cache/dnf,sharing=locked \
    bash /usr/bin/misp-enable-epel.sh &&\
    microdnf install --nodocs --setopt=install_weak_deps=0 \
        libglvnd-glx poppler-cpp zbar && \
    groupadd -g 1112 misp-modules &&\
    useradd -u 1112 -r -g 1112 --create-home --system misp-modules

# Install misp-module wheels, compiled in the python-build stage:
COPY --chown=1112:1112 --from=python-build /opt/venv /opt/venv
COPY --chown=1112:1112 --from=python-build /misp-modules-commit /opt/venv/
ENV PATH="/opt/venv/bin:$PATH"
USER misp-modules
RUN \
    python3 -m pip install --upgrade pip &&\
    python3 -m pip install sentry-sdk==1.5.1 &&\
    echo "__all__ = ['cache', 'sentry']" > /opt/venv/lib/python3.9/site-packages/misp_modules/helpers/__init__.py
    # permissions massaging previously seen here made obsolete though use of venv!

# Binaries need to be available for non-"misp-modules" UIDs:
#ENV PATH="/home/misp-modules/.local/bin:${PATH}"
ENV PYTHONPATH=":/opt/venv/lib/python3.9/site-packages"
COPY sentry.py /opt/venv/lib/python3.9/site-packages/misp_modules/helpers/

EXPOSE 6666/tcp
CMD ["/opt/venv/bin/misp-modules", "-l", "0.0.0.0"]
HEALTHCHECK CMD curl -s -o /dev/null localhost:6666/modules
