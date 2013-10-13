package MediaWords::CM::Mine::Spider;

use strict;
use warnings;

use Modern::Perl "2012";
use MediaWords::CommonLibs;

use MediaWords::DB;

# Returns a human-readable non-false reason if there are any
# controversy_seed_urls for the current controversy with urls that don't
# already exist in the controversy and for which processed = 'f'
sub _controversy_has_unprocessed_seed_urls($$)
{
    my ( $db, $controversies_id ) = @_;

    my $result = $db->query(
        <<EOF,

        SELECT 1
        FROM controversy_seed_urls
        WHERE controversies_id = ?
          AND processed = 'f'

          -- "<...> with urls that don't already exist in the controversy"
          AND NOT EXISTS (
            SELECT 1
            FROM stories, controversy_stories
            WHERE stories.url = controversy_seed_urls.url
              AND stories.stories_id = controversy_stories.stories_id
              AND controversy_stories.controversies_id = controversy_seed_urls.controversies_id
          )
        LIMIT 1

EOF
        $controversies_id
    )->hash;

    if ( $result )
    {
        return 'controversy has unprocessed seed URLs';
    }
    else
    {
        return 0;
    }
}

# Returns a human-readable non-false reason if there are any
# query_story_search_stories_map entries for the current
# controversy.query_story_searches_id with stories that have not been imported
sub _controversy_has_unimported_stories($$)
{
    my ( $db, $controversies_id ) = @_;

    my $result = $db->query(
        <<EOF,

        -- Copy-pasted from import_query_story_search()
        SELECT 1
        FROM stories s
            JOIN query_story_searches_stories_map qsssm
                ON qsssm.stories_id = s.stories_id
            JOIN controversies c
                ON qsssm.query_story_searches_id = c.query_story_searches_id
               AND c.controversies_id = ?
            LEFT JOIN controversy_query_story_searches_imported_stories_map cm
                ON cm.stories_id = s.stories_id AND cm.controversies_id = c.controversies_id
               AND cm.stories_id IS NULL
        LIMIT 1

EOF
        $controversies_id
    )->hash;

    if ( $result )
    {
        return 'controversy has unimported stories';
    }
    else
    {
        return 0;
    }
}

# Returns a human-readable non-false reason if there are controversy_stories
# for the current controversy for which link_mined = 'f'
sub _controversy_has_unmined_links($$)
{
    my ( $db, $controversies_id ) = @_;

    my $result = $db->query(
        <<EOF,

        SELECT 1
        FROM controversy_stories
        WHERE controversies_id = ?
          AND link_mined = 'f'
        LIMIT 1

EOF
        $controversies_id
    )->hash;

    if ( $result )
    {
        return 'controversy has unmined links';
    }
    else
    {
        return 0;
    }
}

# Returns a human-readable non-false reason if there are any controversy_links
# for the current controversy for which ref_stories_id = null
sub _controversy_has_undefined_stories_id_refs($$)
{
    my ( $db, $controversies_id ) = @_;

    my $result = $db->query(
        <<EOF,

        SELECT 1
        FROM controversy_links
        WHERE controversies_id = ?
          AND ref_stories_id IS NULL
        LIMIT 1

EOF
        $controversies_id
    )->hash;

    if ( $result )
    {
        return 'controversy has undefined "stories_id" references';
    }
    else
    {
        return 0;
    }
}

# Returns arrayref of human-readable reasons if the CM spider
# (MediaWords::CM::Mine::mine_controversy()) needs to be run.
#
# Returns false if it doesn't.
sub spider_needs_to_be_run($$)
{
    my ( $db, $controversies_id ) = @_;

    my @reason_subrefs = (
        \&_controversy_has_unprocessed_seed_urls, \&_controversy_has_unimported_stories,
        \&_controversy_has_unmined_links,         \&_controversy_has_undefined_stories_id_refs
    );
    my @reasons;

    foreach my $reason_subref ( @reason_subrefs )
    {
        my $reason = $reason_subref->( $db, $controversies_id );
        if ( $reason )
        {
            push( @reasons, $reason );
        }
    }

    if ( scalar @reasons )
    {
        return \@reasons;
    }
    else
    {
        return 0;
    }
}

1;
