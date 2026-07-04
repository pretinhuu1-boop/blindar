#!/usr/bin/env bash
# FIXTURE BOA — honra o CMD.
set -e
python manage.py migrate
exec "$@"
