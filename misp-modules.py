#!/usr/bin/env python3
import os
import sys
from misp_modules.__main__ import main

sentry_dsn = os.getenv("SENTRY_DSN")

if sentry_dsn:
    import sentry_sdk
    from sentry_sdk.integrations.tornado import TornadoIntegration

    sentry_sdk.init(
        dsn=sentry_dsn,
        ca_certs="/etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem",  # CentOS cert bundle
        integrations=[TornadoIntegration()]
    )

sys.exit(main())
