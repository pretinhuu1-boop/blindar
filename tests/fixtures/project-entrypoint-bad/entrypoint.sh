#!/usr/bin/env bash
# FIXTURE VULNERAVEL — comentarios neutros.
set -e
python manage.py migrate
python manage.py seed
python -m myapp.server
