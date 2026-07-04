# FIXTURE BOA — autogenerate saudavel.
from alembic import context
from myapp.models import Base

target_metadata = Base.metadata


def run_migrations_online():
    pass
