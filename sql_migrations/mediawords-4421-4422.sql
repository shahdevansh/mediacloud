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

ALTER TABLE media_edits
	-- Don't reference the "media" table in the SQL diff because ALTER TABLE
	-- will fill "media_id" with zeroes, and media.media_id = 0 might not exist.
	--
	-- Also, make the default value of media_edits.media_id = 0 because at this
	-- point we don't know which specific media was edited (someone has to
	-- create those references by hand).
	--
	-- Later, after creating manual references from media_edits.media_id to
	-- media.media_id, one should ALTER this table further as such:
	--
	--     ALTER TABLE media_edits ALTER COLUMN media_id DROP DEFAULT;
	--     ALTER TABLE media_edits ADD CONSTRAINT media_edits_media_id_fkey
	--         FOREIGN KEY (media_id) REFERENCES media(media_id)
	--         ON DELETE NO ACTION ON UPDATE NO ACTION DEFERRABLE;
    --
	ADD COLUMN media_id INT         NOT NULL DEFAULT 0;

CREATE INDEX media_edits_media_id ON media_edits (media_id);
CREATE INDEX media_edits_edited_field ON media_edits (edited_field);
CREATE INDEX media_edits_users_email ON media_edits (users_email);
CREATE INDEX story_edits_stories_id ON story_edits (stories_id);
CREATE INDEX story_edits_edited_field ON story_edits (edited_field);
CREATE INDEX story_edits_users_email ON story_edits (users_email);


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

--
-- 2 of 2. Reset the database version.
--
SELECT set_database_schema_version();

