#!/bin/sh
set -e
cd /app
bundle install --quiet
exec "$@"
