#!/bin/bash
set -e

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" <<-EOSQL
	\connect $POSTGRES_DB;

	CREATE EXTENSION IF NOT EXISTS citext;

	create role read_only;
	create role read_write in role read_only;
	create role admin in role read_write;

	create schema base authorization admin;
	create schema audit authorization admin;

  alter database $POSTGRES_DB set search_path = base,public;

	grant connect on database $POSTGRES_DB to read_only;
	grant usage on schema public to read_only;
	grant usage on schema base to read_only;
	grant usage on schema audit to read_only;
	grant temporary on database $POSTGRES_DB to read_write;
	
	alter default privileges for role admin in schema base grant select on tables to read_only;
	
	alter default privileges for role admin in schema base grant select, insert, update, delete on tables to read_write;
	alter default privileges for role admin in schema base grant usage, select, update on sequences to read_write;
	alter default privileges for role admin in schema base grant execute on functions to read_write;

	alter default privileges for role admin in schema base grant all on tables to admin;
	alter default privileges for role admin in schema base grant all on sequences to admin;
	alter default privileges for role admin in schema base grant all on functions to admin;

	alter default privileges for role admin in schema audit grant select on tables to read_only;
	alter default privileges for role admin in schema audit grant insert on tables to read_write;
	alter default privileges for role admin in schema audit grant usage on sequences to read_write;

  set role admin;

  CREATE TABLE template (
    orig_insert_ts     TIMESTAMP NOT NULL DEFAULT current_timestamp,
    last_change_ts     TIMESTAMP NOT NULL DEFAULT current_timestamp,
    app_last_change_by TEXT      NULL,
    db_last_change_by  TEXT      NOT NULL DEFAULT current_user
  );

  CREATE OR REPLACE FUNCTION update_last_change()
    RETURNS TRIGGER AS \$\$
  BEGIN
    new.last_change_ts := current_timestamp;
    new.db_last_change_by := current_user;
    RETURN new;
  END;
  \$\$ LANGUAGE plpgsql;

  CREATE OR REPLACE FUNCTION audit_change()
    RETURNS TRIGGER AS
  \$\$
  DECLARE
    aud_table_name TEXT;
    query_op       TEXT;
    base_record    RECORD;
  BEGIN
    aud_table_name := 'audit.' || TG_TABLE_NAME;
    query_op := 'INSERT INTO ' || aud_table_name || ' VALUES (default, ''' || TG_OP || ''', (\$1).*)';

    IF (TG_OP = 'INSERT' OR TG_OP = 'UPDATE')
    THEN
      base_record := NEW;
    ELSE
      base_record := OLD;
      base_record.last_change_ts = current_timestamp;
      base_record.db_last_change_by = current_user;
    END IF;

    EXECUTE query_op
    USING base_record;
    RETURN NULL;
  END;
  \$\$ LANGUAGE plpgsql;
EOSQL