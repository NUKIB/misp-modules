# Base image with python3.9 and enabled powertools and repo repo
FROM quay.io/centos/centos:stream8 as base
ENV LC_ALL=C.UTF-8
RUN sed -i -e 's/enabled=0/enabled=1/' /etc/yum.repos.d/CentOS-Stream-PowerTools.repo && \
    yum update -y && \
    yum install -y epel-release && \
    yum module install -y python39 && \
    alternatives --set python3 /usr/bin/python3.9 && \
    rm -rf /var/cache/yum

# Build stage that will build required python modules
FROM base as python-build
ENV MISP_MODULES_VERSION main
RUN yum install -y python39-devel python39-wheel gcc gcc-c++ git-core ssdeep-devel poppler-cpp-devel && \
    mkdir /source && \
    cd /source && \
    curl -L https://github.com/MISP/misp-modules/archive/$MISP_MODULES_VERSION.tar.gz | tar zx --strip-components=1 && \
    pip3 wheel --wheel-dir /wheels -r REQUIREMENTS

# Final image
FROM base
# Use system certificates for python requests library
ENV REQUESTS_CA_BUNDLE=/etc/ssl/certs/ca-bundle.crt
COPY --from=python-build /wheels /wheels
RUN yum install -y libglvnd-glx poppler-cpp zbar && \
    rm -rf /var/cache/yum && \
    useradd --create-home --system --user-group misp-modules
USER misp-modules
RUN pip3 --no-cache-dir install --no-warn-script-location --user /wheels/* pyfaup censys uwhois sentry-sdk==1.5.1 && \
    echo "__all__ = ['cache', 'sentry']" > /home/misp-modules/.local/lib/python3.9/site-packages/misp_modules/helpers/__init__.py && \
    chmod -R u-w /home/misp-modules/.local/
COPY sentry.py /home/misp-modules/.local/lib/python3.9/site-packages/misp_modules/helpers/

EXPOSE 6666/tcp
CMD ["/home/misp-modules/.local/bin/misp-modules", "-l", "0.0.0.0"]
HEALTHCHECK CMD curl -s -o /dev/null localhost:6666/modules
