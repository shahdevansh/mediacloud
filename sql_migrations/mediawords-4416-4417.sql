--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4416 and 4417.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4416, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4417, import this SQL file:
--
--     psql mediacloud < mediawords-4416-4417.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--

--
-- 1 of 2. Import the output of 'apgdiff':
--

create index controversy_links_controversy on controversy_links ( controversies_id );


-- The following ALTERs actually belong to the r4418-r4419 SQL diff, but
-- they're being pushed as a hot patch to the current release branch.
ALTER INDEX auth_users_roles_map_users_id_roles_id
	RENAME TO auth_users_roles_map_auth_users_id_auth_roles_id;

ALTER TABLE auth_users
	RENAME users_id TO auth_users_id;

ALTER TABLE auth_roles
	RENAME roles_id TO auth_roles_id;

ALTER TABLE auth_users_roles_map
	RENAME auth_users_roles_map TO auth_users_roles_map_id;
ALTER TABLE auth_users_roles_map
	RENAME users_id TO auth_users_id;
ALTER TABLE auth_users_roles_map
	RENAME roles_id TO auth_roles_id;



CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE
    
    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4417;
    
BEGIN

    -- Update / set database schema version
    DELETE FROM database_variables WHERE name = 'database-schema-version';
    INSERT INTO database_variables (name, value) VALUES ('database-schema-version', MEDIACLOUD_DATABASE_SCHEMA_VERSION::int);

    return true;
    
END;
$$
LANGUAGE 'plpgsql';


--
-- 2 of 2. Reset the database version.
--
SELECT set_database_schema_version();
