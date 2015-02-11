--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4478 and 4479.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4478, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4479, import this SQL file:
--
--     psql mediacloud < mediawords-4478-4479.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--

--
-- 1 of 2. Import the output of 'apgdiff':
--

SET search_path = public, pg_catalog;


DROP FUNCTION upsert_story_bitly_statistics(INT, INT, INT);
DROP FUNCTION num_controversy_stories_without_bitly_statistics(INT);
DROP TABLE story_bitly_statistics;


-- Bit.ly click statistics for stories, broken down into days (sparse table --
-- only days for which there are records are stored)
CREATE TABLE bitly_story_daily_clicks (
    bitly_story_daily_clicks_id SERIAL      PRIMARY KEY,
    stories_id                  INT         NOT NULL REFERENCES stories ON DELETE CASCADE,

    -- Day for which the click count is being saved
    click_date                  DATE        NOT NULL,

    -- Click count
    click_count                 INT         NOT NULL
);
CREATE UNIQUE INDEX bitly_story_daily_clicks_stories_id_date
    ON bitly_story_daily_clicks ( stories_id, click_date );

-- Date ranges for which Bit.ly click counts have been retrieved
CREATE VIEW bitly_story_clicks AS
    SELECT stories_id,
           MIN(click_date) AS click_start_date,
           MAX(click_date) AS click_end_date,
           SUM(click_count) AS click_count
    FROM (
        SELECT stories_id,
               click_date,
               click_count,

               -- 1. Compute a running, gap-less number in chronological order with the window function row_number()
               -- 2. Deduct that from the date column in each row (after converting to integer).
               --    Consecutive days end up with the same date value grp - which has no other purpose or meaning
               --    than to form groups.
               click_date - ROW_NUMBER() OVER (PARTITION BY stories_id ORDER BY click_date)::int AS grp

        FROM bitly_story_daily_clicks
        ) AS bitly_story_daily_clicks_aggregated
    GROUP BY stories_id, grp
    ORDER BY stories_id, grp;

-- Helper to INSERT / UPDATE story's Bit.ly statistics
CREATE FUNCTION upsert_bitly_story_daily_clicks (
    param_stories_id INT,
    param_click_date DATE,
    param_click_count INT
) RETURNS VOID AS
$$
BEGIN

    LOOP
        -- Try UPDATing
        UPDATE bitly_story_daily_clicks
            SET click_count = param_click_count
            WHERE stories_id = param_stories_id
              AND click_date = param_click_date;
        IF FOUND THEN RETURN; END IF;

        -- Nothing to UPDATE, try to INSERT a new record
        BEGIN
            INSERT INTO bitly_story_daily_clicks (stories_id, click_date, click_count)
            VALUES (param_stories_id, param_click_date, param_click_count);
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


-- Bit.ly referrer statistics for stories
CREATE TABLE bitly_story_referrers (
    bitly_story_referrers_id    SERIAL      PRIMARY KEY,
    stories_id                  INT         NOT NULL REFERENCES stories ON DELETE CASCADE,

    -- Day range for which the referrer count is being saved
    referrer_start_date         DATE        NOT NULL,
    referrer_end_date           DATE        NOT NULL,

    -- Referrer count
    referrer_count              INT         NOT NULL
);
CREATE UNIQUE INDEX bitly_story_referrers_stories_id_start_date_end_date
    ON bitly_story_referrers ( stories_id, referrer_start_date, referrer_end_date );

-- Helper to INSERT / UPDATE story's Bit.ly statistics
CREATE FUNCTION upsert_bitly_story_referrers (
    param_stories_id INT,
    param_referrer_start_date DATE,
    param_referrer_end_date DATE,
    param_referrer_count INT
) RETURNS VOID AS
$$
BEGIN

    LOOP
        -- Try UPDATing
        UPDATE bitly_story_referrers
            SET referrer_count = param_referrer_count
            WHERE stories_id = param_stories_id
              AND referrer_start_date = param_referrer_start_date
              AND referrer_end_date = param_referrer_end_date;
        IF FOUND THEN RETURN; END IF;

        -- Nothing to UPDATE, try to INSERT a new record
        BEGIN
            INSERT INTO bitly_story_referrers (stories_id, referrer_start_date, referrer_end_date, referrer_count)
            VALUES (param_stories_id, param_referrer_start_date, param_referrer_end_date, param_referrer_count);
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


-- Bit.ly stories that have gone through the processing chain
-- (some stories are not found on Bit.ly and thus have no stats, so we need to
-- keep a separate table of all processed stories)
CREATE TABLE bitly_processed_stories (
    bitly_story_referrers_id    SERIAL      PRIMARY KEY,
    stories_id                  INT         NOT NULL UNIQUE REFERENCES stories ON DELETE CASCADE
);

-- Helper to INSERT / UPDATE story's Bit.ly statistics
CREATE FUNCTION upsert_bitly_processed_stories (
    param_stories_id INT
) RETURNS VOID AS
$$
DECLARE
    bitly_story_has_been_processed BOOL;
BEGIN

    LOOP
        -- Try UPDATing
        SELECT 1 INTO bitly_story_has_been_processed
        FROM bitly_processed_stories
        WHERE stories_id = param_stories_id;
        IF FOUND THEN RETURN; END IF;

        -- Nothing to UPDATE, try to INSERT a new record
        BEGIN
            INSERT INTO bitly_processed_stories (stories_id)
            VALUES (param_stories_id);
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


-- Helper to check whether a story is enabled for Bit.ly processing
CREATE FUNCTION bitly_story_is_enabled_for_processing (param_stories_id INT) RETURNS BOOLEAN AS
$$
BEGIN

    -- Check if story exists
    IF NOT EXISTS (

        SELECT 1
        FROM stories
        WHERE stories.stories_id = param_stories_id

    ) THEN
        RAISE EXCEPTION 'Story % does not exist.', param_stories_id;
        RETURN FALSE;
    END IF;

    -- Check "controversies.process_with_bitly"
    IF NOT EXISTS (

        SELECT 1 AS story_is_enabled_for_bitly_processing
        FROM controversy_stories
            INNER JOIN controversies ON controversy_stories.controversies_id = controversies.controversies_id
        WHERE controversy_stories.stories_id = param_stories_id
          AND controversies.process_with_bitly = 't'

    ) THEN
        RETURN FALSE;
    END IF;

    -- Things are fine
    RETURN TRUE;

END;
$$
LANGUAGE plpgsql;


-- Helper to return a number of stories for which we don't have Bit.ly statistics yet
CREATE FUNCTION num_controversy_stories_without_bitly_statistics (param_controversies_id INT) RETURNS INT AS
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
        FROM bitly_processed_stories
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
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4477;
    
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
