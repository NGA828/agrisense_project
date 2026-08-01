"""Structured (JSON) logging formatter + request-id aware log record.

Produces single-line JSON log records that are easy to parse in production
(CloudWatch, ELK, Loki...). A ``request_id`` is attached by
``RequestIDMiddleware`` and surfaced in every record so a single user action can
be traced across log lines.
"""

import json
import logging
import threading
import time

# Thread-local holding the current request_id (set by RequestIDMiddleware).
_request_local = threading.local()


def set_request_id(request_id):
    _request_local.request_id = request_id


def clear_request_id():
    try:
        del _request_local.request_id
    except AttributeError:
        pass


class JsonFormatter(logging.Formatter):
    def format(self, record):
        payload = {
            'timestamp': time.strftime('%Y-%m-%dT%H:%M:%S%z'),
            'level': record.levelname,
            'logger': record.name,
            'message': record.getMessage(),
        }
        # Always include the request id when present on the record.
        rid = getattr(record, 'request_id', None)
        if rid:
            payload['request_id'] = rid
        # Include common exception info.
        if record.exc_info:
            payload['exc_info'] = self.formatException(record.exc_info)
        if record.args:
            payload['args'] = [str(a) for a in record.args]
        return json.dumps(payload, ensure_ascii=False)


class RequestIDFilter(logging.Filter):
    """Attach ``request_id`` from the current thread-local (set by middleware)."""

    def filter(self, record):
        rid = getattr(_request_local, 'request_id', None)
        if rid:
            record.request_id = rid
        return True
