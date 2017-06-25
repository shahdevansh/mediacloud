<!-- MEDIACLOUD-TOC-START -->

Table of Contents
=================

   * [Overview](#overview)
   * [Stories](#stories)
      * [Output description](#output-description)
      * [api/v2/stories/single](#apiv2storiessingle)
      * [api/v2/stories/list](#apiv2storieslist)
         * [Query Parameters](#query-parameters)
         * [Example](#example)
   * [Sentences](#sentences)
      * [api/v2/sentences/list](#apiv2sentenceslist)
         * [Query Parameters](#query-parameters-1)
         * [Example](#example-1)
   * [Downloads](#downloads)
      * [api/v2/downloads/single/](#apiv2downloadssingle)
         * [Query Parameters](#query-parameters-2)
      * [api/v2/downloads/list/](#apiv2downloadslist)
      * [Query Parameters](#query-parameters-3)
   * [Tags](#tags)
      * [api/v2/stories/put_tags (PUT)](#apiv2storiesput_tags-put)
         * [Query Parameters](#query-parameters-4)
         * [Input Description](#input-description)
         * [Example](#example-2)
      * [api/v2/sentences/put_tags (PUT)](#apiv2sentencesput_tags-put)
         * [Input Description](#input-description-1)
         * [Example](#example-3)
      * [api/v2/media/put_tags (PUT)](#apiv2mediaput_tags-put)
         * [Input Description](#input-description-2)
         * [Example](#example-4)
      * [api/v2/tags/create (POST)](#apiv2tagscreate-post)
         * [Input Description](#input-description-3)
         * [Example](#example-5)
      * [api/v2/tags/update (PUT)](#apiv2tagsupdate-put)
         * [Input Description](#input-description-4)
         * [Example](#example-6)
      * [api/v2/tag_sets/create (POST)](#apiv2tag_setscreate-post)
         * [Input Description](#input-description-5)
         * [Example](#example-7)
      * [api/v2/tag_sets/update (PUT)](#apiv2tag_setsupdate-put)
         * [Input Description](#input-description-6)
         * [Example](#example-8)
   * [Feeds](#feeds)
      * [api/v2/feeds/create (POST)](#apiv2feedscreate-post)
         * [Input Description](#input-description-7)
         * [Example](#example-9)
      * [api/v2/feeds/update (PUT)](#apiv2feedsupdate-put)
         * [Input Description](#input-description-8)
         * [Example](#example-10)
      * [api/v2/feeds/scrape (POST)](#apiv2feedsscrape-post)
         * [Input Description](#input-description-9)
         * [Example](#example-11)
      * [api/v2/feeds/scrape_status](#apiv2feedsscrape_status)
         * [Input Description](#input-description-10)
         * [Output Description](#output-description-1)
         * [Example](#example-12)
   * [Media](#media)
      * [api/v2/media/create (POST)](#apiv2mediacreate-post)
         * [Input Description](#input-description-11)
         * [Output Description](#output-description-2)
         * [Example](#example-13)
      * [api/v2/media/update (PUT)](#apiv2mediaupdate-put)
         * [Input Description](#input-description-12)
         * [Example](#example-14)
      * [api/v2/media/list_suggestions](#apiv2medialist_suggestions)
         * [Query Parameters](#query-parameters-5)
         * [Example](#example-15)
      * [api/v2/media/mark_suggestion](#apiv2mediamark_suggestion)
         * [Input Description](#input-description-13)
         * [Example](#example-16)

----
<!-- MEDIACLOUD-TOC-END -->


# Overview


This document describes API calls for administrative users. These calls are intended for users running their own install of Media Cloud. Public users of the mediacloud.org API should refer instead to the Media Cloud API 2.0 Spec.  Please refer to the Media Cloud API 2.0 spec for general information on how requests should be constructed.

# Stories

A story represents a single published piece of content.  Each unique URL downloaded from any syndicated feed within a single media source is represented by a single story.  For example, a single New York Times newspaper story is a Media Cloud story, as is a single Instapundit blog post.  Only one story may exist for a given title for each 24 hours within a single media source.

The `story_text` of a story is either the content of the description field in the syndicated field or the extracted
text of the content downloaded from the story's URL at the `collect_date`, depending on whether our full text RSS
detection system has determined that the full text of each story can be found in the RSS of a given media source.

## Output description

The following table describes the meaning and origin of fields returned by the admin API for both api/v2/stories/single and api/v2/stories/list. (The admin API also returns all the fields available through the general API. Refer to the Media Cloud API 2.0 Spec for a list and description of these fields.)

| Field               | Description
| ------------------- | ----------------------------------------------------------------------
| `title`             | The story title as defined in the RSS feed. May contain HTML (depending on the source).
| `description`       | The story description as defined in the RSS feed. May contain HTML (depending on the source).
| `full_text_rss`     | If 1, the text of the story was obtained through the RSS feed.<br />If 0, the text of the story was obtained by extracting the article text from the HTML.
| `story_text`        | The text of the story.<br />If `full_text_rss` is non-zero, this is formed by stripping HTML from the title and description and concatenating them.<br />If `full_text_rss` is zero, this is formed by extracting the article text from the HTML.<br /> Not included by default - see below.
| `story_sentences`   | A list of sentences in the story.<br />Generated from `story_text` by splitting it into sentences and removing any duplicate sentences occurring within the same source for the same week.<br /> Not included by default - see below.
| `raw_1st_download`  | The contents of the first HTML page of the story.<br />Available regardless of the value of `full_text_rss`.<br />*Note:* only provided if the `raw_1st_download` parameter is non-zero.

## api/v2/stories/single

| URL                                  | Function
| ------------------------------------ | ------------------------------------------------------
| `api/v2/stories/single/<stories_id>` | Return the story for which `stories_id` equals `<stories_id>`

## api/v2/stories/list

| URL                             | Function
| ------------------------------- | ---------------------------------
| `api/v2/stories/list` | Return multiple processed stories

### Query Parameters

| Parameter                    | Default | Notes
| ---------------------------- | ------- | ------------------------------------------------------------------------------
| `last_processed_stories_id`  | 0       | Return stories in which the `processed_stories_id` is greater than this value.
| `rows`                       | 20      | Number of stories to return.
| `raw_1st_download`           | 0       | If non-zero, include the full HTML of the first page of the story.
| `sentences`                  | 0       | If non-zero, include the `story_sentences` field described above in the output.
| `text`                       | 0       | If non-zero, include the `story_text` field described above in the output.
| `corenlp`                    | 0       | If non-zero, include the CoreNLP JSON document with each story and each sentence
| `q`                          | null    | If specified, return only results that match the given Solr query.  Only one `q` parameter may be included.
| `fq`                         | null    | If specified, filter results by the given Solr query.  More than one `fq` parameter may be included.


The `last_processed_stories_id` parameter can be used to page through these results. The API will return stories with a
`processed_stories_id` greater than this value.  To get a continuous stream of stories as they are processed by Media Cloud,
the user must make a series of calls to api/v2/stories/list in which `last_processed_stories_id` for each
call is set to the `processed_stories_id` of the last story in the previous call to the API.

*Note:* `stories_id` and `processed_stories_id` are separate values. The order in which stories are processed is different than the `stories_id` order. The processing pipeline involves downloading, extracting, and vectoring stories. Requesting by the `processed_stories_id` field guarantees that the user will receive every story (matching the query criteria if present) in
the order it is processed by the system.

The `q` and `fq` parameters specify queries to be sent to a Solr server that indexes all Media Cloud stories.  The Solr
server provides full text search indexing of each sentence collected by Media Cloud.  All content is stored as individual
sentences.  The api/v2/stories/list call searches for sentences matching the `q` and / or `fq` parameters if specified and
the stories that include at least one sentence returned by the specified query. Refer to the stories_public/list access point in the
Media Cloud API 2.0 Spec for a more detailed description of the `q` and `fq` parameters.

### Example

The output of these calls is in exactly the same format as for the api/v2/stories/single call.

URL: https://api.mediacloud.org/api/v2/stories/list?last_processed_stories_id=8625915

Return a stream of all stories processed by Media Cloud, greater than the `last_processed_stories_id`.

URL: https://api.mediacloud.org/api/v2/stories/list?last_processed_stories_id=2523432&q=sentence:obama+AND+media_id:1

Return a stream of all stories from The New York Times mentioning `'obama'` greater than the given `last_processed_stories_id`.

# Sentences

The `story_text` of every story processed by Media Cloud is parsed into individual sentences.  Duplicate sentences within
the same media source in the same week are dropped (the large majority of those duplicate sentences are
navigational snippets wrongly included in the extracted text by the extractor algorithm).

## api/v2/sentences/list

### Query Parameters

| Parameter | Default | Notes
| --------- | ---------------- | ----------------------------------------------------------------
| `q`       | n/a              | `q` ("query") parameter which is passed directly to Solr
| `fq`      | `null`           | `fq` ("filter query") parameter which is passed directly to Solr
| `start`   | 0                | Passed directly to Solr
| `rows`    | 1000             | Passed directly to Solr
| `sort`    | publish_date_asc | publish_date_asc, publish_date_desc, or random

--------------------------------------------------------------------------------------------------------

Other than 'sort', these parameters are passed directly through to Solr (see above).  The sort parameter must be
one of the listed above and determines the order of the sentences returned.

### Example

Fetch 10 sentences containing the word 'obama' from The New York Times

URL:  https://api.mediacloud.org/api/v2/sentences/list?q=sentence:obama&rows=10&fq=media_id:1

```json
{
  "responseHeader":{
    "params":{
      "sort":"random_1 asc",
      "df":"sentence",
      "wt":"json",
      "q":"sentence:obama",
      "fq":"media_id:1",
      "rows":"10",
      "start":"0"
    },
    "status":0,
    "QTime":20
  },
  "response":{
    "numFound":94171,
    "docs":[
      {
        "sentence":"Mr. Obama played golf on Sunday and again on Monday.",
        "media_id":1,
        "publish_date":"2013-08-13 00:55:48",
        "sentence_number":3,
        "stories_id":146975599,
        "_version_":1465531175907885056,
        "story_sentences_id":"1693567329"
      },
      {
        "sentence":"Without mentioning them by name, it takes on Charles and David Koch, the wealthy conservative businessmen who have opposed Mr. Obama through the political advocacy group Americans for Prosperity.",
        "media_id":1,
        "publish_date":"2012-01-19 01:12:10",
        "sentence_number":5,
        "stories_id":51549022,
        "_version_":1465513962638409730,
        "story_sentences_id":"902231969"
      },
      {
        "sentence":"Former presidential speechwriters said Lincoln’s few words would make it even more difficult for Mr. Obama to find ones that feel fresh.",
        "media_id":1,
        "publish_date":"2013-08-22 00:51:42",
        "sentence_number":36,
        "stories_id":149735751,
        "_version_":1465531727373926400,
        "story_sentences_id":"1723403496"
      },
      {
        "sentence":"Though Mr. Obama is expected to address how the peace process fits into the broader changes in the Middle East, officials said they did not expect him to lay out a detailed American blueprint to revive the negotiations, which have been paralyzed since September.",
        "media_id":1,
        "publish_date":"2011-05-17 17:10:14",
        "sentence_number":9,
        "stories_id":36107537,
        "_version_":1465517874643730432,
        "story_sentences_id":"684054351"
      },
      {
        "sentence":"“The reason I’m so animated about defeating Barack Obama is because he’s failed the American people,” Mr. Romney said, speaking outside at an energy company.",
        "media_id":1,
        "publish_date":"2012-06-14 13:17:37",
        "sentence_number":68,
        "stories_id":169631466,
        "_version_":1465545382125633537,
        "story_sentences_id":"2085799723"
      },
      {
        "sentence":"Sarah Palin said Obama was guilty of “shuck and jive” on Benghazi.",
        "media_id":1,
        "publish_date":"2012-10-27 23:02:01",
        "sentence_number":27,
        "stories_id":92275227,
        "_version_":1465520856365006849,
        "story_sentences_id":"1060529064"
      },
      {
        "sentence":"Still, Democrats openly worried that if Mr. Obama could not drive a harder bargain when he holds most of the cards, he will give up still more Democratic priorities in the coming weeks, when hard deadlines will raise the prospects of a government default first, then a government shutdown.",
        "media_id":1,
        "publish_date":"2013-01-01 02:10:42",
        "sentence_number":24,
        "stories_id":96795610,
        "_version_":1465523519766921216,
        "story_sentences_id":"1112283342"
      },
      {
        "sentence":"Mr. Obama agreed to the far-reaching penalties after the White House negotiated language that would allow him to waive them against foreign financial institutions.",
        "media_id":1,
        "publish_date":"2012-02-06 17:07:35",
        "sentence_number":12,
        "stories_id":72982936,
        "_version_":1465514836620214273,
        "story_sentences_id":"908488464"
      },
      {
        "sentence":"“We believe the Syrian government to be systematically persecuting its own people on a vast scale.” On Tuesday, the Obama administration added to the economic pressure on Mr. Assad’s government, freezing the United States assets of Foreign Minister Walid al-Moualem and two other officials.",
        "media_id":1,
        "publish_date":"2011-08-31 19:30:38",
        "sentence_number":18,
        "stories_id":40984774,
        "_version_":1465516934096224256,
        "story_sentences_id":"762139692"
      },
      {
        "sentence":"Mr. Obama set the standard with the $745 million he raised in 2008 after opting not to participate in the post-Watergate public financing system, under which candidates received taxpayer funds in return for accepting limits on their spending.",
        "media_id":1,
        "publish_date":"2012-06-22 19:30:32",
        "sentence_number":23,
        "stories_id":83442616,
        "_version_":1465520768804716544,
        "story_sentences_id":"983218944"
      }
    ],
    "start":0
  }
}
```

# Downloads

The provides access to the downloads table.

**Note:** Downloads are an internal implementation detail. Most users will be better served by interacting with the API at the story level and should not use this access point.

The fields of the returned objects include all fields in the downloads table within Postgresql plus 'raw_content' which contains the raw HTML is the download was successful. (If the download was not successful 'raw_content' is omitted.


## api/v2/downloads/single/

| URL                              | Function
| -------------------------------- | -------------------------------------------------------------
| `api/v2/downloads/single/<downloads_id>` | Return the downloads source in which `downloads_id` equals `<downloads_id>`

### Query Parameters

None.

## api/v2/downloads/list/

| URL                 | Function
| ------------------- | -----------------------------
| `api/v2/downloads/list` | Return multiple downloads

## Query Parameters

| Parameter                         | Default | Notes
| --------------------------------- | ------- | -----------------------------------------------------------------
| `last_downloads_id`               | 0       | Return downloads sources with a `downloads_id` greater than this value
| `rows`                            | 20      | Number of downloads sources to return. Cannot be larger than 100

# Tags

These calls allow users to edit tag data, including both the metadata of the tags themselves and their associations with stories, sentences, and media.

## api/v2/stories/put_tags (PUT)

| URL                          | Function
| ---------------------------- | --------------------------------------------------
| `api/v2/stories/put_tags`    | Add tags to a story. Must be a PUT request.

### Query Parameters

| Parameter                         | Default | Notes
| --------------------------------- | ------- | -----------------------------------------------------------------
| `clear_tag_sets`                  | 0       | If true, delete all tags in 'add' tag_sets other than the added tags

### Input Description

Input for this call should be a JSON document with a list of records, each with a `stories_id` key and tag keys (see bwlow).  Each record may also contain an `action` key which can have the value of either `add` or `remove`; if not specified, the default `action` is `add`.

To associate a story with more than one tag, include multiple different records with that story's id.
A single call can include multiple stories as well as multiple tags.  Users are encouraged to batch writes for multiple stories into a single call to avoid the web server overhead of many small web service calls.

The tag can be specified with using a `tags_id` key or by specifying a `tag` and a `tag_set` key.  If the latter form
is used, a new tag or tag_set will be created if ti does not already exist for the given value.

If the `clear_tags` parameter is set to 1, this will call will delete all tag associations for the given stories
for each tag_set included in the list of tags other than the tags added by this call.

### Example

URL: https://api.mediacloud.org/aip/v2/stories/put_tags

Input:

```json
[
  {
    "stories_id": 123456,
    "tags_id": "789123",
    "action": "remove"
  }
  {
    "stories_id": 123456,
    "tag": "japan",
    "tag_set": "gv_country"
  }
]
```

Output:

```json
{ "success": 1 }
```

## api/v2/sentences/put_tags (PUT)

| URL                                  | Function
| ------------------------------------ | -----------------------------------------------------------
| `api/v2/sentences/put_tags`          | Add tags to a story sentence. Must be a PUT request.

### Input Description

See input description for stories/put_tags, but replace `stories_id` with `story_sentences_id`.

### Example

URL: https://api.mediacloud.org/aip/v2/story_sentences/put_tags

Input:

```json
[
  {
    "story_sentences_id": 123456,
    "tag": "gv_country:brazil"
  }
  {
    "story_sentences_id": 123456,
    "tag": "gv_country:jaapan"
  }
]
```

Output:

```json
{ "success": 1 }
```

## api/v2/media/put_tags (PUT)

| URL                     | Function                  |
| ----------------------- | ------------------------- |
| `api/v2/media/put_tags` | add tags to media sources |

### Input Description

See input description for stories/put_tags, but replace `stories_id` with `media_id`.

### Example

URL: https://api.mediacloud.org/aip/v2/media/put_tags

Input:

```json
[
  {
    "story_sentences_id": 123456,
    "tag": "gv_country:brazil"
  }
  {
    "story_sentences_id": 123456,
    "tag": "gv_country:jaapan"
  }
]
```

Output:

```json
{ "success": 1 }
```

## api/v2/tags/create (POST)

| URL                            | Function             |
| ------------------------------ | -------------------- |
| `api/v2/tags/create` | Create the given tag |

### Input Description

| Field     | Description                                    |
| ------------- | ---------------------------------------- |
| `tag`         | New name for the tag.                    |
| `label`       | New label for the tag.                   |
| `description` | New description for the tag.             |
| `show_on_media` | Show as an option for searching media sources |
| `show_on_stories` | Show as an option for searching media sources |
| `is_static`   | True if this is a tag whose contents should be expected to remain static over time |

### Example

https://api.mediacloud.org/api/v2/tags/create

Input:

```json
{
    "tag": "sample_tag",
    "label": "Sample Tag",
    "description": "This is a sample tag for an API example.",
    "show_on_media": 0,
    "show_on_stories": 0,
    "is_static": 0
}
```

Output:

```json
{ "tag":
    {
        "tags_id": 123,
        "tag": "sample_tag",
        "label": "Sample Tag",
        "description": "This is a sample tag for an API example.",
        "show_on_media": 0,
        "show_on_stories": 0,
        "is_static": 0
    }    
}
```

## api/v2/tags/update (PUT)

| URL                            | Function             |
| ------------------------------ | -------------------- |
| `api/v2/tags/update` | Update the given tag |

### Input Description

See api/v2/tags/create above.  The update call also requires a tags_id field

### Example

https://api.mediacloud.org/api/v2/tags/update

Input:

```json
{
    "tags_id": 123,
    "tag": "sample_tag_updated"
}
```

Output:

```json
{ "tag":
    {
        "tags_id": 123,
        "tag": "sample_tag_updated",
        "label": "Sample Tag",
        "description": "This is a sample tag for an API example.",
        "show_on_media": 0,
        "show_on_stories": 0,
        "is_static": 0
    }    
}
```

## api/v2/tag_sets/create (POST)

| URL                                   | Function                                 |
| ------------------------------------- | ---------------------------------------- |
| `api/v2/tag_sets/create` | Create a new tag set |

### Input Description

| Field     | Description                            |
| ------------- | -------------------------------- |
| `name`        | New name for the tag set.        |
| `label`       | New label for the tag set.       |
| `description` | New description for the tag set. |

### Example

https://api.mediacloud.org/api/v2/tag_sets/update/

Input:

```json
{
    "nane": "sample_tag_set",
    "label": "Sample Tag Set",
    "description": "This is a sample tag set for an API example"
}
```

Output:

```json
{
    "tag_set":
    {
        "tag_sets_id": 456,
        "nane": "sample_tag_set",
        "label": "Sample Tag Set",
        "description": "This is a sample tag set for an API example"
    }
}
```

## api/v2/tag_sets/update (PUT)

| URL                                   | Function                                 |
| ------------------------------------- | ---------------------------------------- |
| `api/v2/tag_sets/update` | Update the given tag set |

### Input Description

See tags/create above.  The tag_sets/update call also requires a tag_sets_id field.

### Example

https://api.mediacloud.org/api/v2/tag_sets/update

Input:

```json
{
    "tag_sets_id": 456,
    "nane": "sample_tag_set_update",
}
```

Output:

```json
{
    "tag_set":
    {
        "tag_sets_id": 456,
        "nane": "sample_tag_set_update",
        "label": "Sample Tag Set",
        "description": "This is a sample tag set for an API example"
    }
}
```

# Feeds

## api/v2/feeds/create (POST)

| URL                 | Description       |
| ------------------- | ----------------- |
| api/v2/feeds/create | create a new feed |

### Input Description

| Field       | Description                        |
| ----------- | ---------------------------------- |
| media_id    | id of the parent medium (required) |
| name        | human readable name for the feed   |
| url         | feed URL (required)                |
| feed_type   | `syndicated` or `web_page`         |
| feed_status | `active`, `inactive`, `skipped`    |

This call adds a new feed to an existing media source.  The `syndicated` feed_type should be used for RSS, RDF, and ATOM feeds.  The `web_page` feed_type will just download the given URL once a week and treat the URL as a new story each time.  The `active` feed_status will cause the feed to be regularly crawled.  Feeds should be marked as `inactive` if they are functional and may have been crawled at one point but are no longer crawled now (for instance, feeds that have not had a new story in many months are sometimes marked `inactive`)  Feeds should be given the `skipped` feed_type if they are being added merely to indicate to the automatic feed scraping process that the given URL should not be added to the given media source as a feed.

### Example

Create a new feed in media_id 1:

URL: https://api.mediacloud.org/api/v2/feeds/create

Input:

```json
{
  "media_id": 1,
  "name": "New New Times Feed",
  "url": "http://nytimes.com/new/feed",
  "feed_type": "syndicated",
  "feed_status": "active"
}
```

Output:

```json
{ "feed":
    {
      "media_id": 1,
      "name": "New New Times Feed",
      "url": "http://nytimes.com/new/feed",
      "feed_type": "syndicated",
      "feed_status": "active"
    }    
}
```

## api/v2/feeds/update (PUT)

| URL                 | Description             |
| ------------------- | ----------------------- |
| api/v2/feeds/update | update an existing feed |

### Input Description

See api/v2/feeds/create above.  The input document can contain any subset of fields.  The document must also include a `feeds_id` field.  The `media_id` field cannot be changed.  

### Example

Update the `feed_status` of feed 1 to `inactive`.

URL: https://api.mediacloud.org/api/v2/feeds/update

Input:

```json
{
  "feeds_id": 1,
  "feed_status": "inactive"
}
```

Output:

```json
{ "feed":
    {
      "media_id": 1,
      "name": "New New Times Feed",
      "url": "http://nytimes.com/new/feed",
      "feed_type": "syndicated",
      "feed_status": "inactive"
    }    
}
```



## api/v2/feeds/scrape (POST)

| URL                 | Description                         |
| ------------------- | ----------------------------------- |
| api/v2/feeds/scrape | scrape a media source for new feeds |

This end point scrapes through the web site of the given media source to try to discover new feeds.  

This call queues a scraping job on the backend, which can take a few minutes or a few hours to complete. You can
check the status of the scraping process for a given media source by calling `api/v2/feeds/scrape_status`.  The call
will return the state of the job created to scrape the media source.

### Input Description

| Field    | Description                              |
| -------- | ---------------------------------------- |
| media_id | id of media source to discover new feeds for |

### Example

URL: https://api.medicloud.org/api/v2/feeds/scrape

Input:

```json
{
  "media_id": 1
}
```



Output:

```json
{
    "job_states": [
        {
            "media_id": 1,
            "job_states_id": 1,
            "last_updated": "2017-01-26 14:27:04.781095",
            "message": null,
            "state": "queued"
        }
    ]
}    
```

## api/v2/feeds/scrape_status

| URL                 | Description                         |
| ------------------- | ----------------------------------- |
| api/v2/feeds/scrape_status | check the status of feed scraping jobs |

This end point lists the status of feed scraping jobs (see `api/v2/feeds/scrape` above).  Feed scraping jobs
can be started manually for a specific media source, via a scheduled job (every media source is rescraped every
six months at least), or by adding a media source for the first time.

If called with a media_id input, the call returns all jobs for the given media source, sorted by the
latest first.  If called with no input, the call returns the last 100 feed scraping jobs from all
media sources.

### Input Description

| Field    | Description                              |
| -------- | ---------------------------------------- |
| media_id | id of media source to query for feed scraping jobs|

### Output Description

| Field    | Description                              |
| -------- | ---------------------------------------- |
| state | one of queued, running, completed, or error |
| message | error message of state is 'error' |
| last_updated | date of last state change |
| media_id | id of media being scraped |

### Example

URL: https://api.medicloud.org/api/v2/feeds/scrape_status

Input:

```json
{
  "media_id": 1
}
```



Output:

```json
{
    "job_states": [
        {
            "media_id": 1,
            "job_states_id": 1,
            "last_updated": "2017-01-26 14:27:04.781095",
            "message": null,
            "state": "queued"
        }
    ]
}    
```


# Media

## api/v2/media/create (POST)

| URL                 | Description               |
| ------------------- | ------------------------- |
| api/v2/media/create | create a new media source |

This call will create one or more media sources with the given information, if no existing media source matching the input already exists.  The call will return a status indicating whether each media source already exists along with the media_id of either the new or the existing media source.

### Input Description

| Field             | Description                              |
| ----------------- | ---------------------------------------- |
| url               | home page of media source (required)     |
| name              | unique, human readable name for source (default scraped) |
| foreign_rss_links | true if the link elements in the source's RSS feeds are largely links to other sites, for aggregators for instance (default false) |
| content_delay     | delay URL downloads for this feed this many hours (default 0) |
| feeds             | list of syndicated feed URLs (default none) |
| tags_ids          | list of tags to which to associate the media source (default none) |
| editor_notes      | notes about the source for internal media cloud consumption (default none) |
| public_notes      | notes about the source for public consumption ( default none) |
| is_monitored      | true if the source is manually monitored for completeness by the Media Cloud team (default false) |

The end point accepts either a single JSON record in the above format or a list of records in the same format.

The only required field for a media source is the URL.  The name will be assigned to the HTML title at the media source URL if no name is provided.  A feed scraping job will be queued if no feeds are specified.

The `foreign_rss_links` field should be used only if the link elements themselves in the source's feeds point to external urls.  This flag tells the spider not to treat spidered stories matching those external links as if they belong to this media source.

The `content_delay` field is useful for sources that make many changes to their stories immediately after first publication  Media Cloud only collects each story once, so if the story will change dramatically it can be best to wait a few hour before downloading it.

If an existing media source is found for a given record:

* any tags in `tags_id` will be added to the media source and
* if the source contains no active feeds, either the listed feeds will be added to the media source or, if no feeds are listed, a feed scraping job will be queued.

Other than the above, no other updates will be made to the existing media source during this call.

### Output Description

| Field    | Description                            |
| -------- | -------------------------------------- |
| status   | `new`, `existing`, or `error`          |
| media_id | id of the new or existing media source |
| url      | URL of processed record                |
| error    | error message for `error` status URLs  |


The output is always a list of records with the fields described above.  The output will include one record for each input record.

### Example

URL: https://api.mediacloud.org/api/v2/media/create (PUT)

Input:

```json
[
  {
    "name": "New York Times",
    "url": "http://nytimes.com"
  },
  {
    "name": "Yew Tork Nimes",
    "url": "http://ytnimes.com"
  }
]

```

Output:

```json
[
  {
    "status:": "existing",
    "media_id": 1,
    "url": "http://nytimes.com"
  },
  {
    "status": "new",
    "media_id": 123456,
    "url": "http://ytnimes.com"
  }
]
```

## api/v2/media/update (PUT)

| URL                 | Description                     |
| ------------------- | ------------------------------- |
| api/v2/media/update | update an existing media source |

This call updates a single existing media source.

### Input Description

See api/v2/media/create end point above for possible input fields.  The input record must also include a `media_id` field with an id of an existing media source.  The `feeds` and `tags_ids` fields may not be include in an update call (use the `api/v2/media/put_tags` and `api/v2/feeds/*` calls instead).

### Example

URL: https://api.mediacloud.org/api/v2/media/update

Input:

```json
{
  "media_id": 123456,
  "url": "http://www.ytnimes.com"
}
```

Output:

```json
{ "success": 1 }
```

## api/v2/media/list_suggestions

| URL                             | Description                            |
| ------------------------------- | -------------------------------------- |
| `api/v2/media/list_suggestions` | list suggestions for new media sources |

Suggestions will be listed in the order that they were submitted.

### Query Parameters

| Parameter | Default | Notes                                    |
| --------- | ------- | ---------------------------------------- |
| all       | false   | list all suggestions, including those that have been approved or rejected |
| tags_id   | null    | return only suggestions associated with the given tags_id |

### Example

URL: https://api.mediacloud.org/api/v2/media/list_suggestions

Output:

```json
[
  {
    "email": "hroberts@cyber.law.harvard.edu",
    "auth_users_id": 123,
    "url": "http://mediacloud.org",
    "feed_url": "http://mediacloud.org/feed/",
    "reason": "Media Cloud is a great project",
    "tags_ids": [ 123, 456 ],
    "date_submitted": "2016-11-20 07:42:00",
    "date_marked": "",
    "media_suggestions_id": 1,
    "status": "pending",
    "mark_reason": "",
    "media_id": null
  }
]
```

## api/v2/media/mark_suggestion


| URL                             | Description                       |
| ------------------------------- | --------------------------------- |
| `api/v2/media/mark_suggestion` | approve a media source suggestion |

Mark a media suggestion as having been approved or rejected.  Marking a suggestion as approve or rejected will change the status of the suggestions to 'approved' or 'rejected' and make it not appear in the results listed by `api/v2/media/suggestions/list` unless the `all` parameter is submitted.

Note that marking a suggestion as approved does not automatically create the media source as well.  If you want to create the media source in addition to marking the suggestion, you have to call `api/v2/media/create`.

### Input Description

| Field                | Description                              |
| -------------------- | ---------------------------------------- |
| media_suggestions_id | suggestion id (required)                 |
| status               | 'pending', 'approved' or 'rejected' (required)      |
| mark_reason          | reason for approving or rejecting        |
| media_id             | associated the given media source with an 'approved' suggestion (required for 'approved') |

### Example

URL: https://api.mediacloud.org/api/v2/media/mark_suggestion

Input:

```json
[
  {
    "media_suggestions_id": 1,
    "status": "approved",
    "mark_reason": "Media Cloud is great",
    "media_id": 2
  }
]
```

Output:

```json
{ "success": 1 }
```
