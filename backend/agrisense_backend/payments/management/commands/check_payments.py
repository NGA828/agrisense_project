"""Check payment configuration without initiating a charge."""
from django.core.management.base import BaseCommand, CommandError

from payments.gateway import get_gateway, payment_methods, PaymentError


class Command(BaseCommand):
    help = 'Check enabled payment methods. --check-auth tests MTN credentials without charging.'

    def add_arguments(self, parser):
        parser.add_argument('--check-auth', action='store_true',
                            help='Request an MTN access token (no money movement).')

    def handle(self, *args, **options):
        methods = payment_methods()
        for method in methods:
            mode = method.get('environment', 'disabled')
            self.stdout.write(f"{method['id']}: {'READY' if method['available'] else 'UNAVAILABLE'} ({mode})")
            self.stdout.write('  ' + method['message'])
        if not any(m['available'] for m in methods):
            raise CommandError('No payment gateway is ready. See docs/PAYMENTS_SETUP.md.')
        if options['check_auth']:
            try:
                gateway = get_gateway('MTN_MOMO')
                if gateway.provider == 'sandbox':
                    self.stdout.write('Local simulation: no external authentication to test.')
                else:
                    gateway._token()
                    self.stdout.write(self.style.SUCCESS('MTN authentication succeeded. No charge was made.'))
            except PaymentError as exc:
                raise CommandError(str(exc)) from exc
        self.stdout.write('Real checkout still requires payer approval and a verified final status.')
