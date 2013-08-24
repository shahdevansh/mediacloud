--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4421 and 4422.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4421, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4422, import this SQL file:
--
--     psql mediacloud < mediawords-4421-4422.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--

--
-- 1 of 2. Import the output of 'apgdiff':
--

SET search_path = public, pg_catalog;

CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE
    
    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4422;
    
BEGIN

    -- Update / set database schema version
    DELETE FROM database_variables WHERE name = 'database-schema-version';
    INSERT INTO database_variables (name, value) VALUES ('database-schema-version', MEDIACLOUD_DATABASE_SCHEMA_VERSION::int);

    return true;
    
END;
$$
LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION get_random_gridfs_downloads_id(max_downloads_id INTEGER) RETURNS integer AS $$

    DECLARE
        result INTEGER;
        random_downloads_id INTEGER;
    
    BEGIN

        <<find_random_downloads_id>>
        LOOP        
            -- Generate a random download ID
            SELECT (max_downloads_id * random())::int INTO random_downloads_id;

            RAISE NOTICE 'Attempting to fetch download %', random_downloads_id;

            -- Try to select a download with that download ID
            -- and other conditions
            SELECT downloads_id INTO result
            FROM downloads
            WHERE downloads_id = random_downloads_id
              AND state = 'success'
              AND file_status != 'missing'
              AND path NOT LIKE 'content:%'
              AND path != ''  -- some paths are empty
            LIMIT 1;

            IF NOT FOUND THEN
                CONTINUE find_random_downloads_id;
            END IF;

            -- At this point a download is found
            EXIT find_random_downloads_id;
            
        END LOOP find_random_downloads_id;

        RETURN result;
    END

$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION get_random_gridfs_downloads_id(max_downloads_id INTEGER) IS '
    Get a random download ID that is stored in GridFS and thus is expected to be backed up to S3.

    Treat Tar, file and GridFS downloads alike (it is expected that all of those are stored in GridFS).

    The function is used by the ./script/mediawords_compare_random_gridfs_and_s3_downloads.pl script
    to verify whether or not GridFS downloads are being successfully backed up to S3.

    Usage example (in plpgsql):
        SELECT MAX(downloads_id) INTO max_downloads_id FROM downloads;
        SELECT get_random_gridfs_downloads_id(max_downloads_id) AS random_downloads_id;
    ';

--
-- 2 of 2. Reset the database version.
--
SELECT set_database_schema_version();

