Story Processing Flow
=====================

This document provides an overview of the data processing flow for each story.

The overall process is documented in [story_processing_flow.pdf](diagrams/story_processing_flow.pdf).

The story processing flow consists of five components: the crawler, the extractor, the CoreNLP annotator, the solr
import, the bitly fetcher, and the geotagger.  The crawler, extractor, CoreNLP annotator, and bitly fetchers all run via
[supervisor](supervisor.markdown)  on the core media cloud server.  The extractor, CoreNLP annotator, and bitly fetchers
all run as jobs. The geotagger runs from a separate codebase on a separate server.  The Solr import process runs from
the same code base but from a separate machine in the production media cloud setup.

Media Cloud organizes its content collection around media sources, feeds, and stories.  Media sources are publications
like the New York Times.  Feeds are syndicated feeds like atom, rss, or rdf feeds.  Every feed belongs to a single media
source.  Multiple feeds may belong to a media source (some media sources have hundreds).  Stories are the individual
items published in RSS feeds.  Each story belongs to a single media source but may belong to multiple feeds within
the same media source.

Order of Operations
------------------

The order of the operations described below is:

crawl -> extract -> optional annotation -> Solr import

As described below, bitly fetching happens 3 and 30 days after story publication, and each bitly fetch triggers another Solr import.

Crawler
-------

The crawler is responsible downloading all feeds and stories.  The crawler consists of the provider, the engine, and
a specified number of fetcher/handler processes.  The engine hands URLs to the fetchers to download.  The handlers
store the downloaded content.  If the content is a feed, parse the feed to find new stories and add those to the
download queue.  More details about the crawler are [here](crawler.markdown).

Extractor
---------

The extractors are responsible for parsing the substantive text from the raw HTML of each story and storing it in the
download_texts table.  The extractor also parses the download_text into sentences and stores those sentences in the
story_sentences table.  An extractor job is queued by the crawler handler for each story it downloads.  More
information in the extractor [here](extractor.markdown).

CoreNLP Annotator
-----------------

The CoreNLP annotators are responsible for generating annotations using the stanford CoreNLP library for stories
belonging to some media sources.  The extractor queues a CoreNLP annotation job for each extracted story in a media
source marked for annotation. The actual CoreNLP generation is performed by a separate machine running a web service on
top of the stanford CoreNLP libraries.  More information on the CoreNLP annotation process [here](corenlp.markdown).

Processed Stories ID
--------------------
Once all a story is crawled, extracted, and annotated, it is marked as ready for consumption by creating a
processed_stories_id for the story.  This processed_stories_id is used to provide API clients with a stream of stories
that are ready for consumption.  It is also used to indicate that the story is ready for import into Solr.  

The processed_stories_id is stories in the processed_stories table.  A given stories_id can be associated with more
one processed_stories_id.  Each time a story is reprocessed (re-extracted or re-annotated), a new processed_stories_id
is created for that story.  The processed_stories_id is created by the extractor worker for stories that are not marked
for annotation and by the annotation worker otherwise.

Solr Importer
-------------

The Solr importer checks for any stories present in processed_stories that are new or have been updated
in some way since the last update (in production, we run a Solr import hourly).  Solr imports stories with each
story_sentence as a separate document.  More information on our Solr setup [here](solr.markdown).

Bitly Fetcher
-------------

A bitly fetcher runs for each story 3 days after it is first created and then again 30 days later for each story that
had each at least one bitly click on the first fetch.  The 3 day fetch is queued for the story when the story is
extracted.  The bitly fetcher calls the bitly API to find the number of bitly clicks for each story.  More information
on the bitly fetching [here](bitly.markdown).

Geotagging Client
-----------------
The geotagging client adds a set of tags to each story that indicate that the story is about that location.  The
geotagger operates entirely through the API.  It periodically calls the API to download all new stories in media sources
that we want to geotag, including the CoreNLP annotation for each; generates the geotagging information based on the
entity data in the CoreNLP annotation; and then writes any tags for each story back to the core system through the api.
The geotagger is run as a separate codebase, available
[here](https://github.com/mitmedialab/MediaCloud-GeoCoder).  A separate service to rename the geotags more nicely runs independently, and is [available here](https://github.com/mitmedialab/MediaCloud-GeoTag-Labeller). It parses the text for tags using a separate run instance of the [CLIFF-CLAVIN geoparser](https://github.com/mitmedialab/MediaCloud-GeoCoder).

NYT Themes
----------
The NYT theme client adds a set of tags to each story that indicates what them the story is about, based on a model of 
themes trained on the NYT corpus. A "theme" is something like "politics", "education", etc. That tagger opearates entirely 
through the API.  It periodically calls the API to download all new stories in media sources that we want to tag; generates
the tagging information based on running the text through the trained model; and then writes any tags for each story back
to the core system through the api.
The tagger is run as a separate codebase, available
[here](https://github.com/mitmedialab/MediaCloud-NewsLabeller).
