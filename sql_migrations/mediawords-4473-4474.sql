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


-- Returns date ranges for which we don't have Bit.ly data (clicks or
-- referrers)
--
-- We're assuming in the function that if there's no click data, then there's
-- no referrer data either (as both click and referrer data are being fetched
-- together), so we're testing only the "clicks" data.
CREATE FUNCTION bitly_date_ranges_without_data (
    param_stories_id INT,
    param_start_date DATE,
    param_end_date DATE
)
RETURNS TABLE (
    stories_id INT,
    uncovered_start_date DATE,
    uncovered_end_date DATE
) AS $$
DECLARE
    story_is_enabled_for_processing BOOL;
BEGIN

    SELECT bitly_story_is_enabled_for_processing( param_stories_id ) INTO story_is_enabled_for_processing;
    IF story_is_enabled_for_processing = 'f' THEN
        RAISE EXCEPTION 'Story % is not enabled for Bit.ly processing.', param_stories_id;
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM bitly_processed_stories
        WHERE bitly_processed_stories.stories_id = param_stories_id
    ) THEN
        RAISE NOTICE 'Story % is not processed with Bit.ly at all, '
                     'so the whole date range is assumed to have no data.', param_stories_id;
        RETURN QUERY SELECT param_stories_id, param_start_date, param_end_date;
    END IF;

    RETURN QUERY
    WITH uncovered_dates AS (

        -- Select only the days for which there is no record in the
        -- "bitly_story_daily_clicks" table
        SELECT day AS uncovered_date
        FROM (

                -- Generate a list of all days between two dates
                SELECT date_trunc('day', days_between_dates)::date AS day
                FROM generate_series (
                    param_start_date::timestamp,
                    param_end_date::timestamp,
                    '1 day'::interval
                ) AS days_between_dates

             ) AS generated_days
            LEFT JOIN bitly_story_daily_clicks
                ON generated_days.day = bitly_story_daily_clicks.click_date
               AND bitly_story_daily_clicks.stories_id = param_stories_id
        WHERE bitly_story_daily_clicks.stories_id IS NULL
        ORDER BY day
    )

    -- Generate date ranges from a list of sorted dates, similar to how it's
    -- done in the "bitly_story_clicks" view
    SELECT param_stories_id AS stories_id,
           MIN(uncovered_date) AS uncovered_start_date,
           MAX(uncovered_date) AS uncovered_end_date
    FROM (
            SELECT uncovered_date,
                   uncovered_date - ROW_NUMBER() OVER (ORDER BY uncovered_date)::int AS grp
            FROM uncovered_dates
         ) AS subquery
    GROUP BY grp
    ORDER BY grp;

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

