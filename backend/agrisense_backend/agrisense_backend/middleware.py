"""Request ID middleware for end-to-end tracing.

Every request is assigned a UUID ``X-Request-ID`` (honouring an inbound one so
proxies can correlate). It is exposed on the response header and made available
to the logging layer so all log lines for one request share the same id.
"""

import uuid

from . import logging as _logging


class RequestIDMiddleware:
    def __init__(self, get_response):
        self.get_response = get_response

    def __call__(self, request):
        request_id = request.headers.get('X-Request-ID') or str(uuid.uuid4())
        request.request_id = request_id
        _logging.set_request_id(request_id)

        response = self.get_response(request)
        response['X-Request-ID'] = request_id

        _logging.clear_request_id()
        return response
