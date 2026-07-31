"""One-command local MySQL bootstrap.

Creates the AgriSense database and application user so you never have to
open a raw MySQL prompt:

    python manage.py create_mysql_database
    # prompts for the MySQL root password (or use --admin-password)

Idempotent: safe to re-run. Uses the values from settings/.env
(DB_NAME, DB_USER, DB_PASSWORD, DB_HOST, DB_PORT).
"""

import getpass

import pymysql
from django.conf import settings
from django.core.management.base import BaseCommand, CommandError


def _ident(value):
    """Escape an identifier for use inside backticks."""
    return value.replace('`', '').replace('\x00', '')


def _lit(value):
    """Escape a string literal for MySQL."""
    return str(value).replace('\\', '\\\\').replace("'", "''")


class Command(BaseCommand):
    help = 'Create the MySQL database and app user for AgriSense AI (idempotent).'

    def add_arguments(self, parser):
        parser.add_argument('--admin-user', default=None,
                            help='MySQL admin account (default: root)')
        parser.add_argument('--admin-password', default=None,
                            help='MySQL admin password (prompted if omitted)')

    def handle(self, *args, **options):
        db = settings.DATABASES['default']

        if not db['ENGINE'].endswith('mysql'):
            self.stdout.write(self.style.WARNING(
                f'Default DB engine is "{db["ENGINE"]}" — this command only '
                'applies to MySQL/MariaDB. Nothing to do.'))
            return

        host = db.get('HOST') or 'localhost'
        port = int(db.get('PORT') or 3306)
        db_name = db['NAME']
        db_user = db['USER']
        db_password = db['PASSWORD']

        admin_user = options['admin_user'] or 'root'
        admin_password = options['admin_password']
        if admin_password is None:
            admin_password = getpass.getpass(
                f'Password for MySQL user "{admin_user}" (leave empty for no password): ')
            if admin_password == '':
                admin_password = None

        try:
            conn = pymysql.connect(
                host=host, port=port, user=admin_user, password=admin_password,
                autocommit=True, connect_timeout=10,
            )
        except pymysql.err.OperationalError as exc:
            raise CommandError(
                f'Could not connect to MySQL at {host}:{port} as "{admin_user}". '
                f'Is the server running? Details: {exc}')

        with conn.cursor() as cur:
            cur.execute(
                f"CREATE DATABASE IF NOT EXISTS `{_ident(db_name)}` "
                f"CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci"
            )
            # Cover both localhost and TCP connections (127.0.0.1 resolves
            # through the TCP path and may be matched by '%' only).
            for host_pattern in ('localhost', '%'):
                cur.execute(
                    f"CREATE USER IF NOT EXISTS '{_lit(db_user)}'@'{host_pattern}' "
                    f"IDENTIFIED BY '{_lit(db_password)}'"
                )
                cur.execute(
                    f"GRANT ALL PRIVILEGES ON `{_ident(db_name)}`.* "
                    f"TO '{_lit(db_user)}'@'{host_pattern}'"
                )
            cur.execute('FLUSH PRIVILEGES')
        conn.close()

        self.stdout.write(self.style.SUCCESS(
            f'Database `{db_name}` is ready and user `{db_user}` has full '
            f'access. Next steps:\n'
            f'  1) python manage.py migrate\n'
            f'  2) python manage.py seed_data\n'
            f'  3) python manage.py runserver'))
