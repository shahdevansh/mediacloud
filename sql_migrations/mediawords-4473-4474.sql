--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4473 and 4474.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4473, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4474, import this SQL file:
--
--     psql mediacloud < mediawords-4473-4474.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--

--
-- 1 of 2. Import the output of 'apgdiff':
--

SET search_path = public, pg_catalog;


-- Will recreate right away (with a different name)
DROP FUNCTION upsert_story_bitly_statistics(param_stories_id INT,
    param_bitly_click_count INT,
    param_bitly_referrer_count INT);

-- Rename table and columns
ALTER TABLE story_bitly_statistics
    RENAME TO bitly_story_statistics;

ALTER TABLE bitly_story_statistics
    RENAME COLUMN bitly_click_count TO click_count;
ALTER TABLE bitly_story_statistics
    RENAME COLUMN bitly_referrer_count TO referrer_count;

-- Rename index
ALTER INDEX story_bitly_statistics_stories_id
    RENAME TO bitly_story_statistics_stories_id;

-- Recreate "upsert" function
CREATE OR REPLACE FUNCTION upsert_bitly_story_statistics(param_stories_id INT, param_click_count INT, param_referrer_count INT) RETURNS VOID AS
$$
BEGIN
    LOOP
        -- Try UPDATing
        UPDATE bitly_story_statistics
            SET click_count = param_click_count,
                referrer_count = param_referrer_count
            WHERE stories_id = param_stories_id;
        IF FOUND THEN RETURN; END IF;

        -- Nothing to UPDATE, try to INSERT a new record
        BEGIN
            INSERT INTO bitly_story_statistics (stories_id, click_count, referrer_count)
            VALUES (param_stories_id, param_click_count, param_referrer_count);
            RETURN;
        EXCEPTION WHEN UNIQUE_VIOLATION THEN
            -- If someone else INSERTs the same key concurrently,
            -- we will get a unique-key failure. In that case, do
            -- nothing and loop to try the UPDATE again.
        END;
    END LOOP;
END;
$$
LANGUAGE plpgsql;

-- Implicitly DROP function before recreating it
DROP FUNCTION num_controversy_stories_without_bitly_statistics(param_controversies_id INT);
CREATE FUNCTION num_controversy_stories_without_bitly_statistics(param_controversies_id INT) RETURNS INT AS
$$
DECLARE
    controversy_exists BOOL;
    num_stories_without_bitly_statistics INT;
BEGIN

    SELECT 1 INTO controversy_exists
    FROM controversies
    WHERE controversies_id = param_controversies_id
      AND process_with_bitly = 't';
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Controversy % does not exist or is not set up for Bit.ly processing.', param_controversies_id;
        RETURN FALSE;
    END IF;

    SELECT COUNT(stories_id) INTO num_stories_without_bitly_statistics
    FROM controversy_stories
    WHERE controversies_id = param_controversies_id
      AND stories_id NOT IN (
        SELECT stories_id
        FROM bitly_story_statistics
    )
    GROUP BY controversies_id;
    IF NOT FOUND THEN
        num_stories_without_bitly_statistics := 0;
    END IF;

    RETURN num_stories_without_bitly_statistics;
END;
$$
LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE
    
    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4474;
    
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

