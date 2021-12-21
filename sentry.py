#!/usr/bin/env python3
import os

sentry_dsn = os.getenv("SENTRY_DSN")

if sentry_dsn:
    import sentry_sdk
    from sentry_sdk.integrations.tornado import TornadoIntegration

    sentry_sdk.init(
        dsn=sentry_dsn,
        ca_certs="/etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem",  # CentOS cert bundle
        integrations=[TornadoIntegration()]
    )


def selftest():
    if not sentry_dsn:
        return 'SENTRY_DSN env variable is not set. Helper will be disabled.'


if __name__ == "__main__":
    if selftest() is None:
        sentry_sdk.capture_exception(Exception("This is an example of an error message."))
