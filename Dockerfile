ARG BASE_IMAGE=almalinux:9
ARG PYTHON_VERSION=3.11

# Base image with python3.11 and enabled powertools and epel repo
FROM $BASE_IMAGE AS base
ARG PYTHON_VERSION
ENV PYTHON_VERSION=$PYTHON_VERSION
COPY misp-enable-epel.sh /usr/bin/
RUN set -x && \
    echo "tsflags=nodocs" >> /etc/yum.conf && \
    dnf update -y --setopt=install_weak_deps=False && \
    dnf install -y python${PYTHON_VERSION} python${PYTHON_VERSION}-pip dnf-plugins-core && \
    alternatives --install /usr/bin/python3 python /usr/bin/python${PYTHON_VERSION} 50 && \
    alternatives --install /usr/bin/pip3 pip /usr/bin/pip${PYTHON_VERSION} 50 && \
    bash /usr/bin/misp-enable-epel.sh && \
    dnf config-manager --set-enabled crb && \
    rm -rf /var/cache/dnf

# Build stage that will build required python modules
FROM base AS python-build
RUN dnf install -y --setopt=install_weak_deps=False python${PYTHON_VERSION}-devel python${PYTHON_VERSION}-wheel gcc gcc-c++ git-core poppler-cpp-devel && \
    rm -rf /var/cache/dnf && \
    curl -sSL https://install.python-poetry.org | python3 -
ARG MISP_MODULES_VERSION=main
RUN --mount=type=tmpfs,target=/tmp set -x && \
    mkdir /tmp/source && \
    cd /tmp/source && \
    git config --system http.sslVersion tlsv1.3 && \
    COMMIT=$(git ls-remote https://github.com/MISP/misp-modules.git $MISP_MODULES_VERSION | cut -f1) && \
    curl --proto '=https' --tlsv1.3 --fail -sSL https://github.com/MISP/misp-modules/archive/$COMMIT.tar.gz | tar zx --strip-components=1 && \
    sed -i "s/^python = .*/python = \"$(python3 -c 'import platform; print(platform.python_version())')\"/" pyproject.toml && \
    /root/.local/bin/poetry lock && \
    /root/.local/bin/poetry export --with unstable --without-hashes -f requirements.txt -o requirements.txt && \
    pip3 --no-cache-dir wheel --wheel-dir /wheels -r requirements.txt && \
    pip3 --no-cache-dir wheel --wheel-dir /wheels . && \
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
RUN pip3 --no-cache-dir install --no-warn-script-location --user /wheels/* sentry-sdk==2.16.0 orjson && \
    echo "__all__ = ['cache', 'sentry']" > /home/misp-modules/.local/lib/python${PYTHON_VERSION}/site-packages/misp_modules/helpers/__init__.py && \
    chmod -R u-w /home/misp-modules/.local/
COPY sentry.py /home/misp-modules/.local/lib/python${PYTHON_VERSION}/site-packages/misp_modules/helpers/

EXPOSE 6666/tcp
CMD ["/home/misp-modules/.local/bin/misp-modules", "-l", "0.0.0.0"]
HEALTHCHECK CMD curl -s localhost:6666/healthcheck
