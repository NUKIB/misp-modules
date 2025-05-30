ARG BASE_IMAGE=almalinux:9
ARG PYTHON_VERSION=3.12

# Base image with python3.12 and enabled powertools and epel repo
FROM $BASE_IMAGE AS base
ARG PYTHON_VERSION
ENV PYTHON_VERSION=$PYTHON_VERSION
COPY misp-enable-epel.sh /usr/bin/
RUN set -x && \
    echo "tsflags=nodocs" >> /etc/yum.conf && \
    dnf update -y --setopt=install_weak_deps=False && \
    dnf install -y python${PYTHON_VERSION} && \
    alternatives --install /usr/bin/python3 python /usr/bin/python${PYTHON_VERSION} 50 && \
    bash /usr/bin/misp-enable-epel.sh && \
    rm -rf /var/cache/dnf

# Build stage that will build required python modules
FROM base AS python-build
RUN dnf install -y dnf-plugins-core && \
    dnf config-manager --set-enabled crb && \
    dnf install -y --setopt=install_weak_deps=False python${PYTHON_VERSION}-devel python${PYTHON_VERSION}-pip python${PYTHON_VERSION}-wheel gcc-toolset-14 git-core poppler-cpp-devel && \
    rm -rf /var/cache/dnf && \
    alternatives --install /usr/bin/pip3 pip /usr/bin/pip${PYTHON_VERSION} 50 && \
    curl --proto '=https' --tlsv1.3 -sSL https://install.python-poetry.org | python3 - && \
    /root/.local/bin/poetry self add poetry-plugin-export
ARG MISP_MODULES_VERSION=main
ENV POETRY_CACHE_DIR=/tmp/pypoetry/
RUN --mount=type=tmpfs,target=/tmp source scl_source enable gcc-toolset-14 && \
    set -x && \
    mkdir /tmp/source && \
    cd /tmp/source && \
    git config --system http.sslVersion tlsv1.3 && \
    COMMIT=$(git ls-remote https://github.com/MISP/misp-modules.git $MISP_MODULES_VERSION | cut -f1) && \
    curl --proto '=https' --tlsv1.3 --fail -sSL https://github.com/MISP/misp-modules/archive/$COMMIT.tar.gz | tar zx --strip-components=1 && \
    sed -i "s/^python = .*/python = \"$(python3 -c 'import platform; print(platform.python_version())')\"/" pyproject.toml && \
    /root/.local/bin/poetry lock && \
    /root/.local/bin/poetry export -E all --without-hashes -f requirements.txt -o requirements.txt && \
    pip3 --no-cache-dir wheel --wheel-dir /tmp/wheels -r requirements.txt && \
    pip3 --no-cache-dir wheel --no-deps --wheel-dir /tmp/wheels . && \
    python3 -m venv /misp-modules && \
    /misp-modules/bin/pip --no-cache-dir install /tmp/wheels/* sentry-sdk==2.29.1 && \
    /misp-modules/bin/pip uninstall --yes pip && \
    echo $COMMIT > /misp-modules-commit

# Final image
FROM base
# Use system certificates for python requests library
ENV REQUESTS_CA_BUNDLE=/etc/ssl/certs/ca-bundle.crt
RUN dnf install -y --setopt=install_weak_deps=False libglvnd-glx poppler-cpp zbar && \
    rm -rf /var/cache/dnf && \
    useradd --create-home --system --user-group misp-modules && \
    mkdir /modules
COPY --from=python-build /misp-modules /misp-modules
COPY --from=python-build /misp-modules-commit /home/misp-modules/
COPY --chmod=755 misp-modules.py /usr/bin/misp-modules
USER misp-modules
RUN /usr/bin/misp-modules --test --custom /modules

EXPOSE 6666/tcp
CMD ["/usr/bin/misp-modules", "--listen", "0.0.0.0", "--custom", "/modules"]
HEALTHCHECK CMD curl -s localhost:6666/healthcheck
