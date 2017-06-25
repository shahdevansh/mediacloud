<!-- MEDIACLOUD-TOC-START -->

Table of Contents
=================

   * [Overview](#overview)
      * [Media Cloud Crawler and Core Data Structures](#media-cloud-crawler-and-core-data-structures)
      * [Topic Data Structures](#topic-data-structures)
      * [API URLs](#api-urls)
      * [Snapshots, Timespans, and Foci](#snapshots-timespans-and-foci)
      * [Paging](#paging)
      * [Examples](#examples)
      * [Permissions](#permissions)
   * [Topics](#topics)
      * [topics/create (POST)](#topicscreate-post)
         * [Query Parameters](#query-parameters)
         * [Input Description](#input-description)
         * [Example](#example)
      * [topics/<del>topics_id</del>/update (PUT)](#topicstopics_idupdate-put)
         * [Query Parameters](#query-parameters-1)
         * [Input Description](#input-description-1)
         * [Example](#example-1)
      * [topics/<del>topics_id</del>/spider (POST)](#topicstopics_idspider-post)
         * [Query Parameters](#query-parameters-2)
         * [Output Description](#output-description)
         * [Example](#example-2)
      * [topics/<del>topics_id</del>/spider_status](#topicstopics_idspider_status)
         * [Query Parameters](#query-parameters-3)
         * [Output Description](#output-description-1)
         * [Example](#example-3)
      * [topics/<del>topics_id</del>/iterations/list - TODO](#topicstopics_iditerationslist---todo)
         * [Query Parameters](#query-parameters-4)
         * [Output Description](#output-description-2)
         * [Example](#example-4)
      * [topics/list](#topicslist)
         * [Query Parameters](#query-parameters-5)
         * [Output Description](#output-description-3)
         * [Example](#example-5)
      * [topics/single/<del>topics_id</del>](#topicssingletopics_id)
         * [Query Parameters](#query-parameters-6)
         * [Output Description](#output-description-4)
         * [Example](#example-6)
   * [Permissions](#permissions-1)
      * [topics/permissions/user/list DONE](#topicspermissionsuserlist-done)
         * [Query Parameters](#query-parameters-7)
         * [Output Description](#output-description-5)
         * [Example](#example-7)
      * [topics/<del>topics_id</del>/permissions/list DONE](#topicstopics_idpermissionslist-done)
         * [Query Parameters](#query-parameters-8)
         * [Output Description](#output-description-6)
         * [Example](#example-8)
      * [topics/<del>topics_id</del>/permissions/update (PUT) DONE](#topicstopics_idpermissionsupdate-put-done)
         * [Query Parameters](#query-parameters-9)
         * [Input Description](#input-description-2)
         * [Output Description](#output-description-7)
         * [Example](#example-9)
   * [Stories](#stories)
      * [stories/list](#storieslist)
         * [Query Parameters](#query-parameters-10)
         * [Output Description](#output-description-8)
      * [stories/facebook](#storiesfacebook)
         * [Query Parameters](#query-parameters-11)
         * [Output Description](#output-description-9)
         * [Example](#example-10)
      * [stories/count](#storiescount)
         * [Query Parameters](#query-parameters-12)
         * [Output Description](#output-description-10)
         * [Example](#example-11)
      * [stories/<del>stories_id</del>/update (PUT) - TODO](#storiesstories_idupdate-put---todo)
         * [Query Parameters](#query-parameters-13)
         * [Input Description](#input-description-3)
         * [Output Description](#output-description-11)
         * [Example](#example-12)
      * [stories/<del>stories_id</del>/remove (PUT) - TODO](#storiesstories_idremove-put---todo)
         * [Query Parameters](#query-parameters-14)
         * [Output Description](#output-description-12)
         * [Example](#example-13)
      * [stories/merge (PUT) - TODO](#storiesmerge-put---todo)
         * [Query Parameters](#query-parameters-15)
         * [Input Description](#input-description-4)
         * [Output Description](#output-description-13)
         * [Example](#example-14)
   * [Sentences](#sentences)
      * [sentences/count](#sentencescount)
   * [Media](#media)
      * [media/list](#medialist)
         * [Query Parameters](#query-parameters-16)
         * [Output Description](#output-description-14)
         * [Example](#example-15)
      * [media/map](#mediamap)
         * [Query Parameters](#query-parameters-17)
         * [Output Description](#output-description-15)
         * [Example](#example-16)
      * [media/<del>media_id</del>/remove (PUT) - TODO](#mediamedia_idremove-put---todo)
         * [Query Parameters](#query-parameters-18)
         * [Output Description](#output-description-16)
         * [Example](#example-17)
      * [media/merge (PUT) - TODO](#mediamerge-put---todo)
         * [Query Parameters](#query-parameters-19)
         * [Input Description](#input-description-5)
         * [Output Description](#output-description-17)
         * [Example](#example-18)
   * [Word Counts](#word-counts)
      * [wc/list](#wclist)
   * [Foci](#foci)
      * [Focal Techniques](#focal-techniques)
         * [Focal Technique: Boolean Query](#focal-technique-boolean-query)
      * [focal_set_definitions/create (POST)](#focal_set_definitionscreate-post)
         * [Query Parameters](#query-parameters-20)
         * [Input Description](#input-description-6)
         * [Example](#example-19)
      * [focal_set_definitions/<del>focal_set_definitions_id</del>/update (PUT)](#focal_set_definitionsfocal_set_definitions_idupdate-put)
         * [Query Parameters](#query-parameters-21)
         * [Input Parameters](#input-parameters)
         * [Example](#example-20)
      * [focal_set_definitions/<del>focal_set_definitions_id</del>/delete (PUT)](#focal_set_definitionsfocal_set_definitions_iddelete-put)
         * [Query Parameters](#query-parameters-22)
         * [Output Description](#output-description-18)
         * [Example](#example-21)
      * [focal_set_definitions/list](#focal_set_definitionslist)
         * [Query Parameters](#query-parameters-23)
         * [Output Description](#output-description-19)
         * [Example](#example-22)
      * [focal_sets/list](#focal_setslist)
         * [Query Parameters](#query-parameters-24)
         * [Output Description](#output-description-20)
         * [Example](#example-23)
      * [focus_definitions/create (POST)](#focus_definitionscreate-post)
         * [Query Parameters](#query-parameters-25)
         * [Input Description](#input-description-7)
         * [Example](#example-24)
      * [focus_definitions/<del>focus_definitions_id</del>/update (PUT)](#focus_definitionsfocus_definitions_idupdate-put)
         * [Query Parameters](#query-parameters-26)
         * [Input Description](#input-description-8)
         * [Example](#example-25)
      * [focus_definitions/<del>focus_definitions_id</del>/delete (PUT)](#focus_definitionsfocus_definitions_iddelete-put)
         * [Query Parameters](#query-parameters-27)
         * [Output Description](#output-description-21)
         * [Example](#example-26)
      * [focus_definitions/list](#focus_definitionslist)
         * [Query Parameters](#query-parameters-28)
         * [Output Description](#output-description-22)
         * [Example](#example-27)
      * [foci/list](#focilist)
         * [Query Parameters](#query-parameters-29)
         * [Ouput Description](#ouput-description)
         * [Example](#example-28)
   * [Snapshots](#snapshots)
      * [snapshots/generate (POST)](#snapshotsgenerate-post)
         * [Query Parameters](#query-parameters-30)
         * [Input Description](#input-description-9)
         * [Output Description](#output-description-23)
         * [Example](#example-29)
      * [snapshots/generate_status](#snapshotsgenerate_status)
         * [Query Parameters](#query-parameters-31)
         * [Input Description](#input-description-10)
         * [Output Description](#output-description-24)
         * [Example](#example-30)
         * [snapshots/list](#snapshotslist)
         * [Query Paramaters](#query-paramaters)
         * [Output Description](#output-description-25)
         * [Example](#example-31)
      * [snapshots/<del>snapshots_id</del>/update (PUT) - TODO](#snapshotssnapshots_idupdate-put---todo)
         * [Query Parameters](#query-parameters-32)
         * [Input Description](#input-description-11)
         * [Output Description](#output-description-26)
         * [Example](#example-32)
   * [Timespans](#timespans)
      * [timespans/list](#timespanslist)
         * [Query Parameters](#query-parameters-33)
         * [Output Description](#output-description-27)
         * [Example](#example-33)
      * [timespans/add_dates (PUT) - TODO](#timespansadd_dates-put---todo)
         * [Query Parameters](#query-parameters-34)
         * [Input Description](#input-description-12)
         * [Output Description](#output-description-28)
         * [Example](#example-34)
      * [timespans/list_dates - TODO](#timespanslist_dates---todo)
         * [Query Parameters](#query-parameters-35)
         * [Output Description](#output-description-29)
         * [Example](#example-35)

----
<!-- MEDIACLOUD-TOC-END -->


# Overview

This document described the Media Cloud Topics API.  The Topics API is a subset of the larger Media Cloud API.  The Topics API provides access to data about Media Cloud Topics and related data.  For a fuller understanding of Media Cloud data structures and for information about *Authentication*, *Request Limits*, the API *Python Client*, and *Errors*, see the documentation for the main [link: main api] Media Cloud API.

The topics API is currently under development and is available only to Media Cloud team members and select beta testers.  Email us at info@mediacloud.org if you would like to beta test the Topics API.

A *topic* currently may be created only by the Media Cloud team, though we occasionally run topics for external researchers.

## Media Cloud Crawler and Core Data Structures

The core Media Cloud data are stored as *media*, *feeds*, and *stories*.  

A *medium* (or *media source*) is a publisher, which can be a big mainstream media publisher like the New York Times, an
activist site like fightforthefuture.org, or even a site that does not publish regular news-like stories, such as Wikipedia.  

A *feed* is a syndicated feed (RSS, RDF, ATOM) from which Media Cloud pulls stories for a given *media source*.  A given
*media source* may have anywhere from zero *feeds* (in which case we do not regularly crawl the site for new content) up
to hundreds of feeds (for a site like the New York Times to make sure we collect all of its content).

A *story* represents a single published piece of content within a *media source*.  Each *story* has a unique URL within
a given *media source*, even though a single *story* might be published under multiple urls.  Media Cloud tries
to deduplicate stories by title.

The Media Cloud crawler regularly downloads every *feed* within its database and parses out all URLs from each *feed*.
It downloads every new URL it discovers and adds a *story* for that URL, as long as the story is not a duplicate for
the given *media source*.  The Media Cloud archive consists primarily of *stories* collected by this crawler.

## Topic Data Structures

A Media Cloud *topic* is a set of stories relevant to some subject.  The topic spider starts by searching for a
set of stories relevant to the story within the Media Cloud archive and then spiders URLs from those
stories to find more relevant stories, then iteratively repeats the process 15 times.

After the spidering is complete, a *topic* consists of a set of relevant *stories*, *links* between those stories, the
*media* that published those *stories*, and social media metrics about the *stories* and *media*.  The various topics /
end points provide access to all of this raw data as well as various of various analytical processes applied to this
data.

## API URLs

All URLs in the topics API are in the form:

`https://api.mediacloud.org/api/v2/topics/~topics_id~/stories/list`

For example, the following will return all stories in the latest snapshot of topic id 1344.

`https://api.mediacloud.org/api/v2/topics/1344/stories/list`

## Snapshots, Timespans, and Foci

Each *topic* is viewed through one of its *snapshots*.  A *snapshot* is static dump of all data from a topic at
a given point in time.  The data within a *snapshot* will never change, so changes to a *topic* are not visible
until a new *snapshot* is made.

Within a *snapshot*, data can be viewed overall, or through some combination of a *focus* and a *timespan*.

A *focus* consists of a subset of stories within a *topic* defined by some user configured *focal technique*.  For
example, a 'trump' *focus* within a 'US Election' *topic* would be defined using the 'Boolean Query' *focal technique*
as all stories matching the query 'trump'.  Each individual *focus* belongs to exactly one *focal set*.  A *focal set*
provides a way of collecting together *foci* for easy comparison to one another.

A *timespan* displays the *topic* as if it exists only of stories either published within the date range of the
*timespan* or linked to by a story published within the date range of the *timespan*.

*Topics*, *snapshots*, *foci*, and *timespans* are strictly hierarchical.  Every *snapshot* belongs to a single
*topic*.  Every *focus* belongs to a single *snapshot*, and every *timespan* belongs to either a single *focus* or the
null *focus*.  Specifying a *focus* implies the parent *snapshot* of that *focus*.  Specifying a *timespan* implies the
parent *focus* (and by implication the parent *snapshot*), or else the null *focus* within the parent *snapshot*.

* topic
  * snapshot
    * focus
      * timespan

Every URL that returns data from a *topic* accepts optional *spanshots_id*, *timespans_id*, and *foci_id* parameters.

If no *snapshots_id* is specified, the call returns data from the latest *snapshot* generated for the *topic*.  If no
*timespans_id* is specified, the call returns data from the overall *timespan* of the given *snapshot* and *focus*.  If
no *foci_id* is specified, the call assumes the null *focus*.  If multiple of these parameters are specified,
they must point to the same *topic* / *snapshot* / *focus* / *timespan* or an error will be returned (for instance, a
call that specifies a *snapshots_id* for a *snapshot* in a *topic* different from the one specified in the URL, an error
will be returned).


## Paging

For calls that support paging, each URL supports a *limit* parameter and a *link_id* parameter.  For these calls, only
*limit* results will be returned at a time, and a set of *link_ids* will be returned along with the results.  To get the
current set of results again, or the previous or next page of results, call the same end point with only the *key* and
*link_id* parameters. The *link_id* parameter includes state that remembers all of the parameters from the original
call.

For example, the following is a paged response:

```json
{
    "stories":
    [
        {   
            "stories_id": 168326235,
            "media_id": 18047,
            "bitly_click_count": 182,
            "collect_date": "2013-10-26 09:25:39",
            "publish_date": "2012-10-24 16:09:26",
            "inlink_count": 531,
            "language": "en",
            "title": "Donald J. Trump (realDonaldTrump) on Twitter",
            "url": "https://twitter.com/realDonaldTrump",
            "outlink_count": 0,
            "guid": "https://twitter.com/realDonaldTrump"
        }
    ],
    "link_ids":
    {
        "current": 123456,
        "previous": 456789,
        "next": 789123
    }
}
```

After receiving that response, you can use the following URL with no other parameters to fetch the next page of results:

`https://api.mediacloud.org/api/v2/topics/1/stories/list?link_id=789123`

When the system has reached the end of the results, it will return an empty list and a null 'next' *link_id*.

*link_ids* are persistent — they can be safely used to refer to a given result forever (for instance, as an identifier for a link shortener).

## Examples

The section for each end point includes an example call and response for that end point.  For end points that return multiple results, we generally only show a single result (for instance a single story) for the sake of documentation brevity.  All *Input* examples are JSON documents.

## Permissions

The topics API assigns read, write, and admin permissions to individual users.  Read permission allows the given user to view all data within the topic.  Write permission grants read permission and also allows the user to perform all operations on the topic -- including spidering, snapshotting, and merging — other editing permissions.  Admin permission grants write permission and also allows all the user to edit the permissions for the topic.

Each topic also has an 'public' flag.  If that flag is set to true, then all users will have implicit read permission for that topic.

Permssions for the authenticated user for a given topic are included in the topics/list and topics/single calls (note that a given topic will not be visible in either call if the authenticated user does not have read permission for it).  Other calls to list and read permissions are available from the permissions/* end points.

# Topics

## topics/create (POST)

`https://api.mediacloud.org/api/v2/topics/create`

Create and return a new *topic*.

### Query Parameters

(no parameters)

### Input Description

The topics/create call accepts as input the following fields described in the Output Description of the topics/list call: name, solr_seed_query, description, max_iterations, start_date, end_date, is_public, ch_monitor_id, twitter_topics_id, media_ids, media_tags_ids. Required fields are: name, solr_seed_query, description, start_date, end_date, media_ids and media_tags_ids.  Either media_ids or media_tags_ids must be included and not be an empty list.

### Example

Create a new topic:

`https://api.mediacloud.org/api/v2/topics/create`

Input:

```json
{
    "name": "immigration 2015",
    "description": "immigration coverage during 2015",
    "solr_seed_query": "immigration AND (+publish_date:[2016-01-01T00:00:00Z TO 2016-06-15T23:59:59Z]) AND tags_id_media:8875027",
    "max_iterations": 15,
    "start_date": "2015-01-01",
    "end_date": "2015-12-31",
    "is_public": 1,
    "media_tags_ids": [ 123 ],
    "max_stories": 50000
}
```
Response:

```json
{
  "topics":
  [
    {
      "topics_id": 1390,
      "name": "immigration 2015",
      "description": "immigration coverage during 2015",
      "pattern": "[[:<:]]immigration",
      "solr_seed_query": "immigration AND (+publish_date:[2016-01-01T00:00:00Z TO 2016-06-15T23:59:59Z]) AND tags_id_media:8875027",
      "max_iterations": 15,
      "start_date": "2015-01-01",
      "end_date": "2015-12-31",
      "state": "created but not queued",
      "is_public": 1,
      "max_stories": 50000,
      "job_queue": "public",
      "media_tags":
      [
          {
              "tags_id": 123,
              "topics_id": 1390,
              "tag": "us_msm",
              "label": "US Mainstream Media",
              "description": "major US mainstream media sources"
          }
      ]
   }
  ]
}
```

## topics/~topics_id~/update (PUT)

`https://api.mediacloud.org/api/v2/topics/~topics_id~/update`

Edit an existing *topic*.

### Query Parameters

(no parameters)

### Input Description

Accepts the same input as the topics/create call.

### Example

Edit the 'immigration 2015' topic.

`https://api.mediacloud.org/api/v2/topics/1390/update`

Input:

```json
{
    "name": "immigration coverage in 2015"
}
```

Response:

```json
{
  "topics":
  [
    {
      "topics_id": 1390,
      "name": "immigration coverage in 2015",
      "description": "immigration coverage during 2015",
      "pattern": "[[:<:]]immigration",
      "solr_seed_query": "immigration AND (+publish_date:[2016-01-01T00:00:00Z TO 2016-06-15T23:59:59Z]) AND tags_id_media:8875027",
      "max_iterations": 15,
      "start_date": "2015-01-01",
      "end_date": "2015-12-31",
      "state": "queued",
      "is_public": 1,
      "media_tags":
      [
          {
              "tags_id": 123,
              "topics_id": 1390,
              "tag": "us_msm",
              "label": "US Mainstream Media",
              "description": "major US mainstream media sources"
          }
      ]
   }
  ]
}
```

## topics/~topics_id~/spider (POST)

`https://api.mediacloud.org/api/v2/topics/~topics_id/spider`

Start a topic spidering job.

Topic spidering is asynchronous.  Once the topic has started spidering, you cannot start another spidering job until the current one is complete.  Public users can only have one pending job for any topic running at once.  A call to this
end point when a job is pending (for any topic for which a public user has write or admin permission) will simply
return the job_state for the existing pending job.

### Query Parameters

(no parameters)

### Output Description

The call returns a `job_state` record with information about the state of the queued spidering job.

### Example

Start a topic spider for the 'U.S. 2016 Election' topic:

`https://api.mediacloud.org/api/v2/topics/spider`

Input:

```json
{ "topics_id": 1404 }
```

Response:

```json
{
    "job_state":
        {
            "topics_id": 1404,
            "job_states_id": 1,
            "last_updated": "2017-01-26 14:27:04.781095",
            "message": null,
            "state": "queued"
        }
}    
```


## topics/~topics_id~/spider_status

`https://api.mediacloud.org/api/v2/topics/~topics_id~/spider_status`

Get a list all spidering jobs started for this topic.

### Query Parameters

| Parameter | Default | Notes |
|-|-|
| topics_id | (required) | topic id |


### Output Description

| Field    | Description                              |
| -------- | ---------------------------------------- |
| state | one of queued, running, completed, or error |
| message | more detailed message about the job state |
| last_updated | date of last state change |
| topics_id | id of media being scraped |

### Example

`https://api.mediacloud.org/api/v2/topics/1404/spider_status`

Response:

```json
{
    "job_states": [
        {
            "topics_id": 1404,
            "job_states_id": 1,
            "last_updated": "2017-01-26 14:27:04.781095",
            "message": null,
            "state": "queued"
        }
    ]
}    
```

## topics/~topics_id~/iterations/list - TODO

`https://api.mediacloud.org/api/v2/topics/~topics_id~/iterations/list`

Return list of spider iterations with a story count for each

### Query Parameters

(no parameters)

### Output Description

| Field       | Description                    |
| ----------- | ------------------------------ |
| iteration   | number of iteration            |
| story_count | number of stories in iteration |

### Example

Get the list of iterations for the 'U.S. 2016 Election' topic:

`https://api.mediacloud.org/api/v2/topics/~topics_id~/iterations/list`

Response:

```json
{
  "iterations":
  [
    {
      "iteration": 0,
      "count": 500,
    },
    {
      "iteration": 1,
      "count": 1000,
    },
    {
      "iteration": 2,
      "count": 300,
    }
  ]
}
```

## topics/list

`https://api.mediacloud.org/api/v2/topics/list`

The topics/list call returns a simple list of topics available in Media Cloud.  The call will only return topics for
which the calling user has read or higher permissions.  

The topics/list call is is only call that does not include a topics_id in the URL.

### Query Parameters

| Parameter | Default | Notes |
|-|-|-|
| name | null | return only topics with a name including the parameter value |
| public | null | return only topics for which is_public is true |

Standard parameters accepted: link_id.

### Output Description

| Field               | Description                              |
| ------------------- | ---------------------------------------- |
| topics_id           | topic id                                 |
| name                | human readable label                     |
| pattern             | regular expression derived from Solr query |
| solr_seed_query     | Solr query used to generate seed stories |
| solr_seed_query_run | boolean indicating whether the Solr seed query has been run to seed the topic |
| description         | human readable description               |
| max_iterations      | maximum number of iterations for spidering |
| start_date          | start of date range for topic            |
| end_date            | end of date range for topic              |
| state               | the current status of the spidering process |
| message             | last error message generated by the spider, if any |
| is_public           | flag indicating whether this topic is readable by all authenticated users |
| user_permission     | permission for user submitting the API request: 'read', 'write', 'admin', or 'none' |
| queue               | which job pool the topic runs in -- 'mc' for internal media cloud jobs and 'public' for public jobs |
| max_stories         | max number of stories allowed in the topic |

### Example

Fetch all topics in Media Cloud:

`https://api.mediacloud.org/api/v2/topics/list`

Response:

```json
{
    "topics":
    [
        {
            "topics_id": 672,
            "name": "network neutrality",
            "patern": "[[:<:]]net.*neutrality",
            "solr_seed_query": "net* and neutrality and +tags_id_media:(8875456 8875460 8875107 8875110 8875109 8875111 8875108 8875028 8875027 8875114 8875113 8875115 8875029 129 2453107 8875031 8875033 8875034 8875471 8876474 8876987 8877928 8878292 8878293 8878294 8878332) AND +publish_date:[2013-12-01T00:00:00Z TO 2015-04-24T00:00:00Z]",
            "solr_seed_query_run": 1,
            "description": "network neutrality",
            "max_iterations": 15,
            "start_date": "2013-12-01",
            "end_date": "2015-04-24",
            "state": "ready",
            "error_message": "",
            "public": 0,
            "user_permission": "admin",
            "queue": "mc",
            "max_stories": 100000,
        }
    ],
    "link_ids":
    {
        "current": 123456,
        "previous": 456789,
        "next": 789123
    }


}
```

## topics/single/~topics_id~

`https://api.mediacloud.org/api/v2/topics/single/~topics_id~`

The topics/single call returns a single topic, if the calling user has permission to read that topic.

### Query Parameters

(no parameters)

### Output Description

(see topics/list)

### Example

Fetch a single topic:

`https://api.mediacloud.org/api/v2/topics/single/672`

Response:

```json
{
    "topics":
    [
        {
            "topics_id": 672,
            "name": "network neutrality",
            "patern": "[[:<:]]net.*neutrality",
            "solr_seed_query": "net* and neutrality and +tags_id_media:(8875456 8875460 8875107 8875110 8875109 8875111 8875108 8875028 8875027 8875114 8875113 8875115 8875029 129 2453107 8875031 8875033 8875034 8875471 8876474 8876987 8877928 8878292 8878293 8878294 8878332) AND +publish_date:[2013-12-01T00:00:00Z TO 2015-04-24T00:00:00Z]",
            "solr_seed_query_run": 1,
            "description": "network neutrality",
            "max_iterations": 15,
            "start_date": "2013-12-01",
            "end_date": "2015-04-24",
            "state": "ready",
            "error_message": "",
            "public": 0,
            "user_permission": "admin",
            "queue": "mc",
            "max_stories": 100000,
        }
    ]
}
```

# Permissions

## topics/permissions/user/list DONE

`https://api.mediacloud.org/api/v2/topics/permissions/user/list`

List all permissions assigned to the authenticated user for all topics.  This list includes only permissions granted specifically to this user.  Topics available for reading through the 'public' flag are not included in this list.

### Query Parameters

(no parameters)

### Output Description

| Field      | Description                              |
| ---------- | :--------------------------------------- |
| email      | email of user granted permission         |
| topics_id  | id of topic to which permission is granted |
| permission | 'read', 'write', or 'admin'              |

### Example

List all permissions belonging to the authenticated user:

`https://api.mediacloud.org/api/v2/topics/permissions/user/list`

Response:

```json
{
  "permissions":
  [
    {
      "email": "hroberts@cyber.law.harvard.edu",
      "topics_id": 1390,
     "permission": "admin"
    }
  ]
}
```

## topics/~topics_id~/permissions/list DONE

`https://api.mediacloud.org/api/v2/topics/~topics_id~/permissions/list`

List all permissions for the given topic.

### Query Parameters

(no parameters)

### Output Description

(see permissions/user/list)

### Example

List all permissions belonging to the given topic:

`https://api.mediacloud.org/api/v2/topics/1394/permissions/list`

Response:

```json
{
  "permissions":
  [
    {
      "email": "hroberts@cyber.law.harvard.edu",
      "topics_id": 1390,
     "permission": "admin"
    },
   {
      "email": "foo@foo.bar",
      "topics_id": 1390,
     "permission": "read"
    }

  ]
}
```

## topics/~topics_id~/permissions/update (PUT) DONE

`https://api.mediacloud.org/api/v2/topics/~topics_id~/permissions/update`

Update permissions for a given user to a given topic.

### Query Parameters

(no parameters)

### Input Description

| Field      | Description                              |
| ---------- | ---------------------------------------- |
| email      | email of user whose permission is to be updated |
| permission | 'read', 'write', 'admin', or 'none'      |

 Only one permission can exist for a given topic for a given user.  Specify 'none' to remove all permissions for the given topic for the given user.

### Output Description

On success, the new permission is returned in the same format as the permissions/list_users end point.  On failure, an error is returned.

### Example

Update the permissions for a given user for a given topic:

`https://api.mediacloud.org/api/v2/topics/~topics_id~/permissions/update`

Input:

```json
{
  "email": "foo@foo.bar",
  "permission": "read"
}
```



Response:

```json
{
  "permissions":
  [
   {
      "email": "foo@foo.bar",
      "topics_id": 1390,
     "permission": "read"
    }
  ]
}
```



# Stories

## stories/list

`https://api.mediacloud.org/api/v2/topics/~topics_id~/stories/list`

The stories list call returns stories in the topic.

### Query Parameters

| Parameter            | Default | Notes                                    |
| -------------------- | ------- | ---------------------------------------- |
| q                    | null    | if specified, return only stories that match the given Solr query |
| sort                 | inlink  | sort field for returned stories; possible values: `inlink`, `social` |
| stories_id           | null    | return only stories matching these stories_ids |
| link_to_stories_id   | null    | return only stories from other media that link to the given stories_id |
| link_from_stories_id | null    | return only stories from other media that are linked from the given stories_id |
| link_to_media_id     | null    | return only stories that link to stories in the given media |
| link_from_media_id   | null    | return only stories that are linked from stories in the given media_id |
| media_id             | null    | return only stories belonging to the given media_ids |
| limit                | 20      | return the given number of stories       |
| link_id              | null    | return stories using the paging link     |

The call will return an error if more than one of the following parameters are specified: `q`, `link_to_stories`, `link_from_stories_id`.  The `stories_id` and `media_id` parameters can be specified more than once to include stories from more than `stories_id` / `media_id`.

For a detailed description of the format of the query specified in `q` parameter, see the entry for [stories_public/list](api_2_0_spec.md) in the main API spec.

Standard parameters accepted: snapshots_id, foci_id, timespans_id, limit, link_id.

### Output Description

| Field                | Description                              |
| -------------------- | ---------------------------------------- |
| stories_id           | story id                                 |
| media_id             | media source id                          |
| media_name           | media source name                        |
| url                  | story URL                                |
| title                | story title                              |
| guid                 | story globally unique identifier         |
| language             | two letter code for story language       |
| publish_date         | publication date of the story, or 'undateable' if the story is not dateable |
| date_is_reliable     | boolean indicating whether the date_guess_method is nearly 100% reliable |
| collect_date         | date the story was collected             |
| inlink_count         | count of hyperlinks from stories in other media in this timespan |
| outlink_count        | count of hyperlinks to stories in other media in this timespan |
| bitly_click_count    | number of clicks on bitly links that resolve to this story's URL |
| facebook_share_count | number of facebook shares for this story's URL |
| foci            | list of foci to which this story belongs |
### Example

Fetch all stories in topic id 1344:

`https://api.mediacloud.org/api/v2/topics/1344/stories/list`

Response:

```json
{
    "stories":
    [
        {   
            "stories_id": 168326235,
            "media_id": 18047,
            "bitly_click_count": 182,
            "collect_date": "2013-10-26 09:25:39",
            "publish_date": "2012-10-24 16:09:26",
            "date_guess_method": "guess_by_og_article_published_time",
            "inlink_count": 531,
            "language": "en",
            "title": "Donald J. Trump (realDonaldTrump) on Twitter",
            "url": "https://twitter.com/realDonaldTrump",
            "outlink_count": 0,
            "guid": "https://twitter.com/realDonaldTrump",
            "foci":
            [
                {
                    "foci_id": 123,
                    "name": "Trump",
                    "focal_set_name": "Candidates"
                }
            ]
        }
    ],
    "link_ids":
    {
        "current": 123456,
        "previous": 456789,
        "next": 789123
    }
}
```

## stories/facebook

`https://api.mediacloud.org/api/v2/topics/~topics_id~/stories/facebook`

Return the current facebook counts for all stories in the topic.  Note that this call returns the current
facebook count data, which may change over time, rather than the snapshotted, static data returned by the
stories/list call.

### Query Parameters

Standard parameters accepted : snapshots_id, foci_id, timespans_id, limit.

### Output Description

| Field | Description                |
| ----- | -------------------------- |
| stories_id | story id |
| facebook_share_count | share count from facebook |
| facebook_comment_count | comment count from facebook |
| facebook_api_collect_date | data on which count data was collected from facebook |

### Example

Return the facebook counts for 3 stories in the given topic.

`https://api.mediacloud.org/api/v2/topics/1404/stories/facebook?limit=3`

Response:

```json
{
   "counts" : [
      {
         "facebook_api_collect_date" : "2016-11-25 04:45:35.636022",
         "facebook_comment_count" : 0,
         "facebook" : 0,
         "stories_id" : 737
      },
      {
         "facebook_api_collect_date" : "2016-11-13 11:35:35.657778",
         "facebook_comment_count" : 0,
         "facebook" : 0,
         "stories_id" : 2884
      },
      {
         "facebook_api_collect_date" : "2016-11-13 11:35:35.783757",
         "facebook_comment_count" : 0,
         "facebook" : 0,
         "stories_id" : 3994
      }
   ],
   "link_ids" : {
      "current" : 21797,
      "next" : 21798
   }
}
```

## stories/count

`https://api.mediacloud.org/api/v2/topics/~topics_id~/stories/count`

Return the number of stories that match the query.

### Query Parameters

| Parameter | Default | Notes                               |
| --------- | ------- | ----------------------------------- |
| q         | null    | count stories that match this query |

For a detailed description of the format of the query specified in `q` parameter, see the entry for [stories_public/list](https://github.com/berkmancenter/mediacloud/blob/release/doc/api_2_0_spec/api_2_0_spec.md#apiv2stories_publiclist) in the main API spec.

Standard parameters accepted : snapshots_id, foci_id, timespans_id, limit.

### Output Description

| Field | Description                |
| ----- | -------------------------- |
| count | number of matching stories |

### Example

Return the number of stories that mention 'immigration' in the 'US Election' topic:

`https://api.mediacloud.org/api/v2/topics/~topics_id~/stories/count?q=immigration`

Response:

```json
{ "count": 123 }
```

## stories/~stories_id~/update (PUT) - TODO

`https://api.mediacloud.org/api/v2/topics/~topics_id~/stories/~stories_id~/update`

Edit and return a story.  Editing a story changes that story for all topics.

### Query Parameters

(no parameters)

### Input Description

| Field        | Description                              |
| ------------ | ---------------------------------------- |
| stories_id   | id of story to edit; required            |
| title        | story title                              |
| publish_date | story publication date in this format: 2016-06-30 15:34:45Z or 'undateable' |

### Output Description

| Field   | Description                              |
| ------- | ---------------------------------------- |
| success | boolean indicating that the story was successfully edited. |

### Example

Edit the publish_date of story 123456:

`https://api.mediacloud.org/api/v2/topics/~topics_id~/stories/~stories_id~/update`

Input:

```json
{
  "publish_date": "2016-05-30 15:34:45"
}
```

Response:

(see stories/list)

## stories/~stories_id~/remove (PUT) - TODO

`https://api.mediacloud.org/api/v2/topics/~topics_id~/stories/~stories_id~/remove`

Remove the given story from the topic (but do not delete it from Media Cloud).

### Query Parameters

(no parameters)

### Output Description

| Field   | Description                              |
| ------- | ---------------------------------------- |
| success | boolean indicating that the story was removed |

### Example

Remove stories_id 12345 from topics_id 1340:

`https://api.mediacloud.org/api/v2/topics/1340/stories/12345/remove`

Response:

```json
{ "success": 1 }
```

## stories/merge (PUT) - TODO

`https://api.mediacloud.org/api/v2/topics/~topics_id~/stories/merge`

Merge one story into another story within this topic.

### Query Parameters

(no parameters)

### Input Description

| Field           | Description                              |
| --------------- | ---------------------------------------- |
| from_stories_id | id of the story to merge into to_stories_id; required |
| to_stories_id   | id of the story into which from_stories_id will be merge; required |

Merging from_stories_id into to_stories_id removes from_stories_id from the topic and merges the outlinks and inlinks of from_stories_id into to_stories_id.

### Output Description

| Field   | Description                              |
| ------- | ---------------------------------------- |
| success | boolean indicating that the story was successfully merged. |

### Example

Merge story 1234 into story 6789:

`https://api.mediacloud.org/api/v2/topics/~topics_id~/stories/merge`

Input:

```json
{
  "from_stories_id": 1234,
  "to_stories_id": 6789
}
```

Response:

```json
{ "success": 1 }
```

# Sentences

## sentences/count

`https://api.mediacloud.org/api/v2/topics/~topics_id~/sentences/count`

Return the numer of sentences that match the query, optionally split by date.

This call behaves exactly like the main API sentences/count call, except:

- This call only searches within the given snapshot
- This call accepts the standard topics parameters: snapshots_id, foci_id, timespans_id

For details about this end point, including parameters, output, and examples, see the [main API](https://github.com/berkmancenter/mediacloud/blob/release/doc/api_2_0_spec/api_2_0_spec.md#apiv2sentencescount).

# Media

## media/list

`https://api.mediacloud.org/api/v2/topics/~topics_id~/media/list`

The media list call returns the list of media in the topic.

### Query Parameters

| Parameter | Default | Notes                                    |
| --------- | ------- | ---------------------------------------- |
| media_id  | null    | return only the specified media          |
| sort      | inlink  | sort field for returned stories; possible values: `inlink`, `social` |
| name      | null    | search for media with the given name     |
| limit     | 20      | return the given number of media         |
| link_id   | null    | return media using the paging link       |

If the `name` parameter is specified, the call returns only media sources that match a case insensitive search specified value. If the specified value is less than 3 characters long, the call returns an empty list.

Standard parameters accepted: snapshots_id, foci_id, timespans_id, limit, link_id.

### Output Description

| Field                | Description                              |
| -------------------- | ---------------------------------------- |
| media_id             | medium id                                |
| name                 | human readable label for medium          |
| url                  | medium URL                               |
| story_count          | number of stories in medium              |
| inlink_count         | sum of the inlink_count for each story in the medium |
| outlink_count        | sum of the outlink_count for each story in the medium |
| bitly_click_count    | sum of the bitly_click_count for each story in the medium |
| facebook_share_count | sum of the facebook for each story in the medium |
| focus_ids            | list of ids of foci to which this medium belongs |

### Example

Return all stories in the medium that match 'twitt':

`https://api.mediacloud.org/api/v2/topics/~topics_id~/media/list?name=twitt`

Response:

```json
{
    "media":
    [
        {
            "bitly_click_count": 303,
            "media_id": 18346,
            "story_count": 3475,
            "name": "Twitter",
            "inlink_count": 8454,
            "url": "http://twitter.com",
            "outlink_count": 72,
            "facebook": 123
        }
    ],
    "link_ids":
    {
        "current": 123456,
        "previous": 456789,
        "next": 789123
    }
}
```
## media/map

`https://api.mediacloud.org/api/v2/topics/~topics_id~/media/map`

The media list call returns a gexf formatted network map of the media in the topic / timespan.

### Query Parameters

| Parameter | Default | Notes                                    |
| --------- | ------- | ---------------------------------------- |
| color_field  | media_type    | node coloring; possible values: `partisan_code`, `media_type`          |
| num_media      | 500  | number of media to map, sorted by media inlinks |
| include_weights | false | include weights on edges (default is to use a weight of 1 for every edge) |
| num_links_per_medium | null | if set, only inclue the top num_links_per_media out links from each medium, sorted by medium_link_counts.link_count and then inlink_count of the target medium |


Standard parameters accepted: snapshots_id, foci_id, timespans_id.

### Output Description

Output is a gexf formatted file, as described here:

https://gephi.org/gexf/format/

### Example

Return the network map for topic id 12:

`https://api.mediacloud.org/api/v2/topics/12/media/map`

## media/~media_id~/remove (PUT) - TODO

`https://api.mediacloud.org/api/v2/topics/~topics_id~/media/~media_id~/remove`

Remove the given medium from the topic (but do not delete it from Media Cloud).

### Query Parameters

(no parameters)

### Output Description

| Field   | Description                              |
| ------- | ---------------------------------------- |
| success | boolean indicating that the medium was removed |

### Example

Remove media_id 1 from the topics_id 1340:

`https://api.mediacloud.org/api/v2/topics/1340/media/1/remove`

Response:

```json
{ "success": 1 }
```

## media/merge (PUT) - TODO

`https://api.mediacloud.org/api/v2/topics/~topics_id~/media/merge`

Merge all stories from one medium into another medium within this topic.

### Query Parameters

(no parameters)

### Input Description

| Field         | Description                              |
| ------------- | ---------------------------------------- |
| from_media_id | id of the medium to merge into to_media_id; required |
| to_media_id   | id of the medium into which from_media_id will be merge; required |

Mergin from_media_id into to_media_id merges all stories of from_media_it into to_media_id.  If a story with a matching URL or title already exists in to_media_id, the call merges those stories as described in stories/merge.  If no matching story exists in to_media_id, a new story is created.

### Output Description

| Field   | Description                              |
| ------- | ---------------------------------------- |
| success | boolean indicating that the story was successfully merged. |

### Example

Merge medium 1 into medium 2:

`https://api.mediacloud.org/api/v2/topics/~topics_id~/media/merge`

Input:

```json
{
  "from_media_id": 1,
  "to_media_id": 2
}
```

Response:

```json
{ "success": 1 }
```

# Word Counts

## wc/list

`https://api.mediacloud.org/api/v2/topics/~topics_id~/wc/list`

Returns sampled counts of the most prevalent words in a topic, optionally restricted to sentences that match a given query.

This call behaves exactly like the main API wc/list call, except:

* This call only searches within the given snapshot
* This call accepts the standard topics parameters: snapshots_id, foci_id, timespans_id

For details about this end point, including parameters, output, and examples, see the [main API](https://github.com/berkmancenter/mediacloud/blob/release/doc/api_2_0_spec/api_2_0_spec.md#apiv2wclist).


# Foci

A *focus* is a set of stories identified through some *focal technique*.  *focal sets* are sets of *foci* that share a *focal technique* and are also usually some substantive theme determined by the user.  For example, a 'U.S. 2016 Election' topic might include a 'Candidates' *focal set* that includes 'trump' and 'clinton' foci, each of which uses a 'Boolean Query' *focal techniqueology* to identify stories relevant to each candidate with a separate boolean query for each.

A specific *focus* exists within a specific *snapshot*.  A single topic might have many 'clinton' *foci*, one for each *snapshot*.  Each *topic* has a number of *focus definion*, each of which tells the system which *foci* to create each time a new *snapshot* is created.  *foci* for new *focus definitions* will be only be created for *snapshots* created after the creation of the *focus definition*.

The relationship of these objects is shown below:

* topic
    * snapshot
        * focus
            * timespan

## Focal Techniques

Media Cloud currently supports the following focal techniques.

* Boolean Query

Details about each focal technique are below.  Among other properties, each focal technique may or not be exclusive.  Exlcusive focal techniques generate *focal sets* in which each story belongs to at most one *focus*.

### Focal Technique: Boolean Query

The Boolean Query focal technique associates a focus with a story by matching that story with a Solr boolean query.  *focal sets* generated by the Boolean Query method are not exclusive.

## focal_set_definitions/create (POST)

`https://api.mediacloud.org/api/topics/~topics_id~/focal_set_definitions/create`

Create and return a new *focal set definiition*  within the given *topic*.

### Query Parameters

(no parameters)

### Input Description

| Field           | Description                              |
| --------------- | ---------------------------------------- |
| name            | short human readable label for focal set definition |
| description     | human readable description of focal set definition |
| focal_technique | focal technique to be used for all focus definitions in this definition |

### Example

Create a 'Candidates' focal set definition in the 'U.S. 2016 Election' topic:

`https://api.mediacloud.org/api/v2/topics/1344/focal_set_definitions/create`

Input:

```json
{
    "name": "Candidates",
    "description": "Stories relevant to each candidate.",
    "focal_techniques": "Boolean Query"
}
```
Response:

```json
{
    "focal_set_definitions":
    [
        {
            "focal_set_definitions_id": 789,
            "topics_id": 456,
            "name": "Candidates",
            "description": "Stories relevant to each candidate.",
            "focal_technique": "Boolean Query",
            "is_exclusive": 0
        }
    ]
}
```

## focal_set_definitions/~focal_set_definitions_id~/update (PUT)

`https://api.mediacloud.org/api/v2/topics/~topics_id~/focal_set_definitions/~focal_set_definitions_id~/update/`

Update the given focal set definition.

### Query Parameters

(no parameters)

### Input Parameters

See *focal_set_definitions/create* for a list of fields.  Only fields that are included in the input are modified.

### Example

Update the name and description of the 'Candidates'  focal set"definition":

`https://api.mediacloud.org/api/v2/topics/1344/focal_set_definitions/789/update`

Input:

```json
{
    "name": "Major Party Candidates",
    "description": "Stories relevant to each major party candidate."
}
```

Response:

```json
{
    "focal_set_definitions":
    [
        {
            "focal_set_definitions_id": 789,
            "topics_id": 456,
            "name": "Major Party Candidates",
            "description": "Stories relevant to each major party candidate.",
            "focal_technique": "Boolean Query",
            "is_exclusive": 0
        }
    ]
}
```

## focal_set_definitions/~focal_set_definitions_id~/delete (PUT)

`https://api.mediacloud.org/api/v2/topics/~topics_id~/focal_set_definitions/~focal_set_definitions_id~/delete`

Delete a focal set definition.

### Query Parameters

(no parameters)

### Output Description

| Field   | Description                              |
| ------- | ---------------------------------------- |
| success | boolean indicating that the focal set defintion was deleted. |

### Example

Delete focal_set_definitions_id 123:

`https://api.mediacloud.org/api/v2/topics/~topics_id~/focal_set_definitions/123/delete`

Response:

```json
{ "success": 1 }
```

## focal_set_definitions/list

`https://api.mediacloud.org/api/v2/topics/~topics_id~/focal_set_definitions/list`

Return a list of all focal set definitions belonging to the given topic.

### Query Parameters

(no parameters)

### Output Description

| Field                    | Description                              |
| ------------------------ | ---------------------------------------- |
| focal_set_definitions_id | focal set defintion id                   |
| name                     | short human readable label for the focal set definition |
| description              | human readable description of the focal set definition |
| focal_technique          | focal technique used for foci in this set |
| is_exclusive             | boolean that indicates whether a given story can only belong to one focus, based on the focal technique |
| focus_defitions          | list of focus definitions belonging to this focal set definition |

### Example

List all focal set definitions associated with the 'U.S. 2016 Elections'"topic":

`https://api.mediacloud.org/api/v2/topics/1344/focal_set_definitions/list`

Response:

```json
{
    "focal_set_definitions":
    [
        {
            "focal_set_definitions_id": 789,
            "topics_id": 456,
            "name": "Major Party Candidates",
            "description": "Stories relevant to each major party candidate.",
            "focal_technique": "Boolean Query",
            "is_exclusive": 0
            "focus_definitions":
            [
                {
                    "focus_definitions_id": 234,
                    "name": "Clinton",
                    "description": "stories that mention Hillary Clinton",
                    "query": "clinton and ( hillary or -bill )"
                }
            ]

        }
    ]
}
```

## focal_sets/list

`https://api.mediacloud.org/api/v2/topics/~topics_id~/focal_sets/list`

List all *focal sets* belonging to the specified *snapshot* in the given *topic*.

### Query Parameters

Standard parameters accepted: snapshots_id, frames_id, timespans_id.

If no snapshots_id is specified, the latest snapshot will be used.  If foci_id or timespans_id is specified, the snapshot containining that focus or timespan will be used.

### Output Description

| Field           | Description                              |
| --------------- | ---------------------------------------- |
| focal_sets_id   | focal set id                             |
| name            | short human readable label for the focal set |
| description     | human readable description of the focal set |
| focal_technique | focal technique used to generate the foci in the focal set |
| is_exclusive    | boolean that indicates whether a given story can only belong to one focus, based on the focal technique |
| foci            | list of foci belonging to this focal set |

### Example

Get a list of *focal sets* in the latest *snapshot* in the 'U.S. 2016 Election' *topic*:

`https://api.mediacloud.org/api/v2/topics/1344/focal_sets_list`

Response:

```json
{
    "focal_sets":
    [
        {
            "focal_sets_id": 34567,
            "name": "Candidates",
            "description": "Stories relevant to each candidate.",
            "focal_technique": "Boolean Query",
            "is_exclusive": 0,
            "foci":
            [
                {
                    "foci_id": 234,
                    "name": "Clinton",
                    "description": "stories that mention Hillary Clinton",
                    "query": "clinton and ( hillary or -bill )",
                    "focal_technique": "Boolean Query"
                }
            ]
        }
    ]
}
```


## focus_definitions/create (POST)

`https://api.mediacloud.org/api/topics/~topics_id~/focus_definitions/create`

Create and return a new *focus definition*  within the given *topic* and *focal set definition*.

### Query Parameters

(no parameters)

### Input Description

| Field                    | Description                              |
| ------------------------ | ---------------------------------------- |
| name                     | short human readable label for foci generated by this definition |
| description              | human readable description for foci generated by this definition |
| query                    | Boolean Query: query used to generate foci generated by this definition |
| focus_set_definitions_id | id of parent focus set definition        |

The input for the *focus definition* depends on the focal technique of the parent *focal set definition*.  The focal technique specific input fields are listed last in the table above and are prefixed with the name of applicable focal technique.

### Example

Create the 'Clinton' *focus definition* within the 'Candidates' *focal set definition* and the 'U.S. 2016 Election' *topic*:

`https://api.mediacloud.org/api/v2/topics/1344/focus_definitions/create`

Input:

```json
{
    "name": "Clinton",
    "description": "stories that mention Hillary Clinton",
    "query": "clinton",
    "focal_set_definitions_id": 789
}
```

Response:

```json
{
    "focus_definitions":
    [
        {
            "focus_definitions_id": 234,
            "name": "Clinton",
            "description": "stories that mention Hillary Clinton",
            "query": "clinton",
            "focal_technique": "Boolean Query"
        }
    ]
}
```


## focus_definitions/~focus_definitions_id~/update (PUT)

`https://api.mediacloud.org/api/v2/topics/~topics_id~/focus_definitions/~focus_definitions_id~/update`

Update the given focus definition.

### Query Parameters

(no parameters)

### Input Description

See *focus_definitions/create* for a list of fields.  Only fields that are included in the input are modified.

### Example

Update the query for the 'Clinton' focus definition:

`https://api.mediacloud.org/api/v2/topics/1344/focus_definitions/234/update`

Input:

```json
{ "query": "clinton and ( hillary or -bill )" }
```

Response:

```json
{
    "focus_definitions":
    [
        {
            "focus_definitions_id": 234,
            "name": "Clinton",
            "description": "stories that mention Hillary Clinton",
            "query": "clinton and ( hillary or -bill )"
        }
    ]
}
```

## focus_definitions/~focus_definitions_id~/delete (PUT)

`https://api.mediacloud.org/api/v2/topics/~topics_id~/focus_definitions/~focus_definitions_id~/delete`

Delete a focus definition.

### Query Parameters

(no parameters)

### Output Description

| Field   | Description                              |
| ------- | ---------------------------------------- |
| success | boolean indicating that the focus definition was deleted. |

### Example

Delete focus_definitions_id 123:

`https://api.mediacloud.org/api/v2/topics/~topics_id~/focus_definitions/123/delete`

Response:

```json
{ "success": 1 }
```

## focus_definitions/list

`https://api.mediacloud.org/api/v2/topics/~topics_id~/focus_definitions/~focal_set_definitions_id~/list`

List all *focus definitions* belonging to the given *focal set definition*.

### Query Parameters

| Parameter               | Default | Notes                                    |
| ----------------------- | ------- | ---------------------------------------- |
| focal_set_defintions_id | none    | id of parent focal set definition - required |

### Output Description

| Field                | Description                              |
| -------------------- | ---------------------------------------- |
| focus_definitions_id | focus definition id                      |
| name                 | short human readable label for foci generated by this definition |
| description          | human readable description for foci generated by this definition |
| query                | Boolean Query: query used to generate foci generated by this definition |

The output for *focus definition* depends on the focal technique of the parent *focal set definition*.  The framing
method specific fields are listed last in the table above and are prefixed with the name of applicable focal technique.

### Example

List all *focus definitions* belonging to the 'Candidates' *focal set definition* of the 'U.S. 2016 Election' *topic*:

`https://api.mediacloud.org/api/v2/topics/1344/focus_definitions/234/list`

Response:

```json
{
    "focus_definitions":
    [
        {
            "focus_definitions_id": 234,
            "name": "Clinton",
            "description": "stories that mention Hillary Clinton",
            "query": "clinton and ( hillary or -bill )"
        }
    ]
}
```

## foci/list

`https://api.mediacloud.org/api/v2/topics/~topics_id~/foci/list`

Return a list of the *foci* belonging to the given *focal set*.

### Query Parameters

| Parameter     | Default | Notes                                 |
| ------------- | ------- | ------------------------------------- |
| focal_sets_id | none    | id of the parent focal set - required |

### Ouput Description

| Field       | Description                              |
| ----------- | ---------------------------------------- |
| foci_id     | focus id                                 |
| name        | short human readable label for the focus |
| description | human readable description of the focus  |
| query       | Boolean Query: query used to generate the focus |

The output for *focus* depends on the focal technique of the parent *focus definition*.  The focal technique specific fields are listed last in the table above and are prefixed with the name of applicable focal technique.

### Example

Get a list of *foci* wihin the 'Candiates' *focal set* of the 'U.S. 2016 Election' *topic*:

`https://api.mediacloud.org/api/v2/topics/1344/foci/list?focal_sets_id=234`

Response:

```json
{
    "foci":
    [
        {
            "foci_id": 234,
            "name": "Clinton",
            "description": "stories that mention Hillary Clinton",
            "query": "clinton and ( hillary or -bill )"
        }
    ]
}
```

# Snapshots

Each *snapshot* contains a static copy of all data within a topic at the time the *snapshot* was made.  All data viewable by the Topics API must be viewed through a *snapshot*.

## snapshots/generate (POST)

`https://api.mediacloud.org/api/v2/topics/~topics_id~/snapshots/generate`

Generate a new *snapshot* for the given topic.  Note that `topics/spider` will generate a snapshot as part of its
spidering process, so this end point only needs to be called to generate an additional snapshot of a topic
without also spidering (for instance after editing the foci definitions).

This is an asynchronous call.  The *snapshot* process will run in the background, and the new *snapshot* will only become visible to the API once the generation is complete.

### Query Parameters

(no parameters)

### Input Description

| Field | Description                              |
| ----- | ---------------------------------------- |
| note  | short text note about the snapshot; optional |

### Output Description

This command will return a job_state object as described in the `snapshots/generate_status` call below.

### Example

Start a new *snapshot* generation job for the 'U.S. 2016 Election' *topic*:

`https://api.mediacloud.org/api/v2/topics/1344/snapshots/generate`

Response:

```json
{
    "job_state":
        {
            "topics_id": 1404,
            "job_states_id": 1,
            "last_updated": "2017-01-26 14:27:04.781095",
            "message": null,
            "state": "queued"
        }
}    
```

## snapshots/generate_status

`https://api.mediacloud.org/api/v2/topics/~topics_id~/snapshots/generate_status`

Return a list of snapshots job_states for the given snapshot;

### Query Parameters

(no parameters)

### Input Description

| Field | Description                              |
| ----- | ---------------------------------------- |
| note  | short text note about the snapshot; optional |

### Output Description

| Field    | Description                              |
| -------- | ---------------------------------------- |
| state | one of queued, running, completed, or error |
| message | more detailed message about the job state |
| last_updated | date of last state change |
| topics_id | id the topic being snapshotted |

### Example

List snapshot jobs for the 'U.S. 2016 Election' *topic*:

`https://api.mediacloud.org/api/v2/topics/1344/snapshots/generate_status`

Response:

```json
{
    "job_states": [
        {
            "topics_id": 1404,
            "job_states_id": 1,
            "last_updated": "2017-01-27 14:27:04.781095",
            "message": null,
            "state": "completed"
        }
    ]
}    
```

### snapshots/list

`https://api.mediacloud.org/api/v2/topics/~topics_id~/snapshots/list`

Return a list of all completed *snapshots* in the given *topic*.

### Query Paramaters

(no parameters)

### Output Description

| Field         | Description                            |
| ------------- | -------------------------------------- |
| snapshots_id  | snapshot id                            |
| snapshot_date | date on which the snapshot was created |
| note          | short text note about the snapshot     |
| state         | state of the snapshotting process      |
| message       | more detailed message about the state of the snapshotting process |
| searchable    | boolean indicating whether timespans are searchable yet |

The state indicates the state of the current snapshot process, including but not limited to 'completed' for a snapshot
whose process has successfully completed and 'error' for a snapshot that failed for some reason.  

Each timespan in a snapshot is queued for text indexing when the snapshot is generated.  This process may take a
few minutes up to a few hours.  The 'searchable' field is set to true once that indexing process is complete.

### Example

Return a list of *snapshots* in the 'U.S. 2016 Election' *topic*:

`https://api.mediacloud.org/api/v2/topics/1344/snapshots/list`

Response:

```json
{
    "snapshots":
    [
        {
            "snapshots_id": 6789,
            "snapshot_date": "2016-09-29 18:14:47.481252",
            "note": "final snapshot for paper analysis",
            "state": "completed"
        }  
    ]
}
```

## snapshots/~snapshots_id~/update (PUT) - TODO

`https://api.mediacloud.org/api/v2/topics/~topics_id~/snapshots/~snapshots_id~/update`

Edit and return the snapshot.

### Query Parameters

(no parameters)

### Input Description

| Field        | Description                        |
| ------------ | ---------------------------------- |
| snapshots_id | snapshot id; required              |
| note         | short text note about the snapshot |

### Output Description

(see snapshots/list)

### Example

Edit the note for snapshot 4567:

`https://api.mediacloud.org/api/v2/topics/~topics_id~/snapshots/~snapshots_id~/update`

Input:

```json
{
  "snapshots_id": 4567,
  "note": "final snapshot for paper analysis"
}
```

Response:

(see snapshots/list)

# Timespans

Each *timespan* is a view of the *topic* that presents the topic as if it consists only of *stories* within the date range of the given *timespan*.

A *story* is included within a *timespan* if the publish_date of the story is within the *timespan* date range or if the *story* is linked to by a *story* that whose publish_date is within date range of the *timespan*.

## timespans/list

`https://api.mediacloud.org/api/v2/topics/~topics_id~/timespans/list`

Return a list of timespans in the current snapshot.

### Query Parameters

Standard parameters accepted: snapshots_id, foci_id, timespans_id.

### Output Description

| Field             | Description                              |
| ----------------- | ---------------------------------------- |
| timespans_id      | timespan id                              |
| period            | type of period covered by timespan; possible values: overall, weekly, monthly, custom |
| start_date        | start of timespan date range             |
| end_date          | end of timespan date range               |
| story_count       | number of stories in timespan            |
| story_link_count  | number of cross media story links in timespan |
| medium_count      | number of distinct media associated with stories in timespan |
| medium_link_count | number of cros media media links in timespan |
| model_r2_mean     | timespan modeling r2 mean                |
| model_r2_stddev   | timespan modeling r2 standard deviation  |
| model_num_media   | number of media include in modeled top media list |
| foci_id           | id of focus to which the timespan belongs |
| snapshots_id      | id of snapshot to which the timespan belongs |

Every *topic* generates the following timespans for every *snapshot*:

* overall - an timespan that includes every story in the topic
* custom all - a custom period timespan that includes all stories within the date range of the topic
* weekly - a weekly timespan for each calendar week in the date range of the topic
* monthly - a monthly timespan for each calendar month in the date range of the topic

Media Cloud needs to guess the date of many of the stories discovered while topic spidering.  We have validated the date guessing to be about 87% accurate for all methods other than the finding a URL in the story URL.  The possiblity of significant date errors make it possible for the Topic Mapper system to wrongly assign stories to a given timespan and to also miscount links within a given timespan (due to stories getting misdated into or out of a given timespan).  To mitigate the risk of drawing the wrong research conclusions from a given timespan, we model what the timespan might look like if dates were wrong with the frequency that our validation tell us that they are wrong within a given timespan.  We then generate a pearson's correlation between the ranks of the top media for the given timespan in our actual data and in each of ten runs of the modeled data.  The model_* fields provide the mean and standard deviations of the square of those correlations.

### Example

Return all *timespans* associated with the latest *snapshot* of the 'U.S. 2016 Election' *topic*:

`https://api.mediacloud.org/api/v2/topics/1344/timespans/list`

Response:

```json
{
    "timespans":
    [
        {
            "timespans_id": 6789,
            "period": "overall",
            "start_date": "2016-01-01",
            "end_date": "2016-12-01",
            "story_count": 10283,
            "story_link_count": 543,
            "medium_count": 2345,
            "medium_link_count": 1543,
            "model_r2_mean": 0.94,
            "model_r2_stddev": 0.04,
            "model_num_media": 143,
            "foci_id": null,
            "snapshots_id": 456
        }
    ]
}
```

## timespans/add_dates (PUT) - TODO

`https://api.meiacloud.org/api/v1/topics/~topics_id~/timespans/add_dates`

Add a date range for which to generate *timespans* for future *spanshots*.

### Query Parameters

(no parameters)

### Input Description

| Field      | Description         |
| ---------- | ------------------- |
| start_date | start of date range |
| end_date   | end of date range   |

### Output Description

| Field   | Description                              |
| ------- | ---------------------------------------- |
| success | boolean indicating whether the spidering job was successfully queued. |

### Example

Add a new *timespan* date range to 'U.S. 2016 Election' *topic*:

`https://api.mediacloud.org/api/v2/topics/1344/timespans/add_dates`

Input:

```json
{
    "start_date": "2016-02-01",
    "end_date": "2016-05-01"
}
```

Response:

```json
{ "success": 1 }
```

## timespans/list_dates - TODO

`https://api.mediacloud.org/api/v2/topics/~topics_id~/timespans/list_dates`

List the dates for which timespans will be generated for each new snapshot.

### Query Parameters

(no parameters)

### Output Description

| Field      | Description                      |
| ---------- | -------------------------------- |
| start_date | start of timespan date range     |
| end_date   | end of timespan date range       |
| period     | 'weekly', 'monthly', or 'custom' |

### Example

List all timespans for the 'U.S. Election 2012' topic:

`https://api.mediacloud.org/api/v2/topics/~topics_id~/timespans/list_dates`

Response:

```json
{
  "dates":
  [
    {
      "start_date": "2016-01-01",
      "end_date": "2016-01-07",
      "period": "weekly"
    }
  ]
}
```
