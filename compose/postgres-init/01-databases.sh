#!/bin/bash
# One database and one role per service (database-per-service). Runs only on an empty data dir.
set -e
for svc in profile product order payment inventory notification; do
  # Quoted identifiers: "order" is a reserved word.
  psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname postgres <<EOSQL
CREATE ROLE "${svc}" LOGIN PASSWORD '${svc}_dev';
CREATE DATABASE "${svc}" OWNER "${svc}";
EOSQL
done
