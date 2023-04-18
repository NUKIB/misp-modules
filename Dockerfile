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

RUN --mount=type=cache,target=/var/cache/dnf \
    # echo /etc/yum.conf && \
    microdnf update --nodocs --setopt=keepcache=0 --setopt=install_weak_deps=0 &&\
    microdnf module enable python39 &&\
    microdnf install curl findutils procps-ng python39 tar util-linux-user &&\
    alternatives --set python3 /usr/bin/python3.9 &&\
    microdnf install dnf dnf-plugins-core &&\
    dnf config-manager --set-enabled powertools &&\
    dnf remove -y --setopt protected_packages=1 dnf dnf-plugins-core
    # microdnf clean all &&\
    # rm -rf /var/cache/dnf

# Build stage that will build required python modules
FROM base as python-build
RUN --mount=type=cache,target=/var/cache/dnf \
    microdnf install --nodocs --setopt=install_weak_deps=0 python39-devel python39-wheel gcc gcc-c++ git-core poppler-cpp-devel
    #rm -rf /var/cache/dnf
ARG MISP_MODULES_VERSION=main
# Use of tmpfs is not allowed in OpenShift build envs: --mount=type=tmpfs,target=/tmp
RUN --mount=type=tmpfs,target=/tmp \
    mkdir /tmp/source && cd /tmp/source && \
    git config --system http.sslVersion tlsv1.3 && \
    COMMIT=$(git ls-remote https://github.com/MISP/misp-modules.git $MISP_MODULES_VERSION | cut -f1) && \
    curl --proto '=https' --tlsv1.3 --fail -sSL https://github.com/MISP/misp-modules/archive/$COMMIT.tar.gz | tar zx --strip-components=1 && \
    pip3 --no-cache-dir wheel --wheel-dir /wheels -r REQUIREMENTS && \
    rm -Rf /tmp/source && \
    echo $COMMIT > /misp-modules-commit

# Final image
FROM base
# Use system certificates for python requests library
ENV REQUESTS_CA_BUNDLE=/etc/ssl/certs/ca-bundle.crt
# EPEL needed for "zbar" (bar code reader) package:
COPY misp-enable-epel.sh /usr/bin/
RUN --mount=type=cache,target=/var/cache/dnf \
    bash /usr/bin/misp-enable-epel.sh &&\
    microdnf install --nodocs --setopt=install_weak_deps=0 libglvnd-glx poppler-cpp zbar && \
    # microdnf clean all &&\
    # rm -rf /var/cache/dnf &&\
    useradd --create-home --system --user-group misp-modules
COPY --from=python-build /wheels /wheels
COPY --from=python-build /misp-modules-commit /home/misp-modules/
USER misp-modules
RUN pip3 --no-cache-dir install --no-warn-script-location --user /wheels/* sentry-sdk==1.5.1 && \
    echo "__all__ = ['cache', 'sentry']" > /home/misp-modules/.local/lib/python3.9/site-packages/misp_modules/helpers/__init__.py && \
    # permissions fixes to allow run from any uuid. (inefficient, but effective.)
    #   - remove write from all files/directories,
    #   - remove execute from non-executable files. 
    chmod u-w /home/misp-modules && \
    find /home/misp-modules -type d -exec chmod 555 {} \; && \
    find /home/misp-modules/.local/etc -type f -exec chmod 444 {} \; && \
    find /home/misp-modules/.local/ -type f -regex '.+\.py$' -exec chmod 444 {} \; && \
    chmod -R u-w /home/misp-modules/.local/
# Binaries need to be available for non-"misp-modules" UIDs:
ENV PATH="/home/misp-modules/.local/bin:${PATH}"
ENV PYTHONPATH=":/home/misp-modules/.local/lib/python3.9/site-packages"
COPY sentry.py /home/misp-modules/.local/lib/python3.9/site-packages/misp_modules/helpers/

EXPOSE 6666/tcp
CMD ["/home/misp-modules/.local/bin/misp-modules", "-l", "0.0.0.0"]
HEALTHCHECK CMD curl -s -o /dev/null localhost:6666/modules
