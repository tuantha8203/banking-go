-- Local-only bootstrap (runs once on an empty volume). Mirrors AD-3/AD-26:
-- databases core, public, admin; per database a <svc>_migrator role (owns schemas/tables, runs goose)
-- and a <svc>_app runtime role (DML only, granted by migrations). Passwords are dev-only.

CREATE ROLE core_migrator   LOGIN PASSWORD 'core_migrator';
CREATE ROLE core_app        LOGIN PASSWORD 'core_app';
CREATE ROLE public_migrator LOGIN PASSWORD 'public_migrator';
CREATE ROLE public_app      LOGIN PASSWORD 'public_app';
CREATE ROLE admin_migrator  LOGIN PASSWORD 'admin_migrator';
CREATE ROLE admin_app       LOGIN PASSWORD 'admin_app';

CREATE DATABASE core     OWNER core_migrator;
CREATE DATABASE "public" OWNER public_migrator;
CREATE DATABASE admin    OWNER admin_migrator;

-- Each role can connect only to its own database.
REVOKE ALL ON DATABASE core     FROM PUBLIC;
REVOKE ALL ON DATABASE "public" FROM PUBLIC;
REVOKE ALL ON DATABASE admin    FROM PUBLIC;
GRANT CONNECT ON DATABASE core     TO core_app;
GRANT CONNECT ON DATABASE "public" TO public_app;
GRANT CONNECT ON DATABASE admin    TO admin_app;

-- Tables the migrator creates later are readable/writable by the app role (DML only).
-- Append-only tables (ledger.journals, ledger.entries, audit.audit_records) revoke UPDATE/DELETE in their migrations.
\connect core
ALTER DEFAULT PRIVILEGES FOR ROLE core_migrator GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO core_app;
ALTER DEFAULT PRIVILEGES FOR ROLE core_migrator GRANT USAGE, SELECT ON SEQUENCES TO core_app;
REVOKE CREATE ON SCHEMA public FROM PUBLIC;

\connect "public"
ALTER DEFAULT PRIVILEGES FOR ROLE public_migrator GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO public_app;
ALTER DEFAULT PRIVILEGES FOR ROLE public_migrator GRANT USAGE, SELECT ON SEQUENCES TO public_app;
REVOKE CREATE ON SCHEMA public FROM PUBLIC;

\connect admin
ALTER DEFAULT PRIVILEGES FOR ROLE admin_migrator GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO admin_app;
ALTER DEFAULT PRIVILEGES FOR ROLE admin_migrator GRANT USAGE, SELECT ON SEQUENCES TO admin_app;
REVOKE CREATE ON SCHEMA public FROM PUBLIC;
