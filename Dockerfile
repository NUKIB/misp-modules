# Base image with python3.11 and enabled powertools and epel repo
ARG BASE_IMAGE=quay.io/centos/centos:stream8
FROM $BASE_IMAGE as base

COPY misp-enable-epel.sh /usr/bin/
RUN set -x && \
    echo "tsflags=nodocs" >> /etc/yum.conf && \
    dnf update -y --setopt=install_weak_deps=False && \
    dnf install -y python3.11 python3.11-pip dnf-plugins-core && \
    alternatives --set python3 /usr/bin/python3.11 && \
    bash /usr/bin/misp-enable-epel.sh && \
    dnf config-manager --set-enabled powertools && \
    rm -rf /var/cache/dnf

# Build stage that will build required python modules
FROM base as python-build
RUN dnf install -y --setopt=install_weak_deps=False python3.11-devel python3.11-wheel gcc gcc-c++ git-core poppler-cpp-devel && \
    rm -rf /var/cache/dnf
ARG MISP_MODULES_VERSION=main
RUN --mount=type=tmpfs,target=/tmp set -x && \
    mkdir /tmp/source && \
    cd /tmp/source && \
    git config --system http.sslVersion tlsv1.3 && \
    COMMIT=$(git ls-remote https://github.com/MISP/misp-modules.git $MISP_MODULES_VERSION | cut -f1) && \
    curl --proto '=https' --tlsv1.3 --fail -sSL https://github.com/MISP/misp-modules/archive/$COMMIT.tar.gz | tar zx --strip-components=1 && \
    pip3 --version && \
    pip3 --no-cache-dir wheel --wheel-dir /wheels -r REQUIREMENTS && \
    echo $COMMIT > /misp-modules-commit

# Final image
FROM base
# Use system certificates for python requests library
ENV REQUESTS_CA_BUNDLE=/etc/ssl/certs/ca-bundle.crt
RUN dnf install -y --setopt=install_weak_deps=False libglvnd-glx poppler-cpp zbar && \
    rm -rf /var/cache/dnf && \
    useradd --create-home --system --user-group misp-modules
COPY --from=python-build /wheels /wheels
COPY --from=python-build /misp-modules-commit /home/misp-modules/
USER misp-modules
RUN pip3 --no-cache-dir install --no-warn-script-location --user /wheels/* sentry-sdk==1.5.1 orjson && \
    echo "__all__ = ['cache', 'sentry']" > /home/misp-modules/.local/lib/python3.11/site-packages/misp_modules/helpers/__init__.py && \
    chmod -R u-w /home/misp-modules/.local/
COPY sentry.py /home/misp-modules/.local/lib/python3.11/site-packages/misp_modules/helpers/

EXPOSE 6666/tcp
CMD ["/home/misp-modules/.local/bin/misp-modules", "-l", "0.0.0.0"]
HEALTHCHECK CMD curl -s -o /dev/null localhost:6666/healthcheck
