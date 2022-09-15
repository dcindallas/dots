#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""

This script downloads RSS/Atom feeds listed in a file named status under
the directory datadir passed as argument.

The status file is a set of rows, each of which has the format:

N\tV\tA\tB\tH\tC\tT\tL\tU\tE\tM

where

N is the number of news not yet shown
V is the number of news available
A is a flag equals to 1 if the feed is active, otherwise is 0
B is a flag equals to 1 for the breaking news, otherwise is 0
H is the hash of the feed's URL (+ a hash salt for breaking news)
C is a color code in the format #XXXXXX, e.g. #FF0000 (red color)
T is the title of the feed
L is the max length of the titles downloaded
U is the feed's URL
E is the etag possibly provided by server
M is the date of the last modification possibly provided by server (cache)

Each field is separated by a tab character (\t).
"""

import argparse
import calendar
import copy
import html
import itertools
import os
import re
import shlex
import tempfile
import time
import sys
try:
    import feedparser
except ImportError:
    print('-- Install feedparser module, please! --')
    sys.exit(0)


def date_handler(date_string):
    """parse a UTC date in DD/MM/YYYY format"""
    _my_date_pattern = re.compile(
        r'(\d{,2})/(\d{,2})/(\d{4})')

    day, month, year = \
        _my_date_pattern.search(date_string).groups()

    return (int(year), int(month), int(day), \
        0, 0, 0, 0, 0, 0)


def parse_args():
    """
    Return a list of command line arguments (using argparse module).
    """
    parser = argparse.ArgumentParser(description=__doc__)

    parser.add_argument(
        '-l', '--last-minutes', default=0, type=int,
        help='download only the news of last n minutes')
    parser.add_argument(
        '-c', '--colors',
        help='list of colors, e.g. "#ff0000,#00ff00,#0000ff"')
    parser.add_argument(
        '-m', '--media-link', action='store_const', const=True, default=False,
        help='save links to audio/video files (useful for podcasts)')
    parser.add_argument(
        '-n', '--number-of-news', default=0,
        help='max number of news per feed (0 means all news)', type=int)
    parser.add_argument(
        'data_dir', help='directory where to save news and status files')

    return parser.parse_args()


class Feed:
    """
    Implement a Feed class, actually a sort of dataclass.
    """

    __slots__ = 'number_of_news', 'number_of_feed_news', 'active', \
        'breaking_news', 'url_hash', 'color', 'title', 'max_title_length', \
        'url', 'etag', 'modified'

    def __init__(self, line):

        fields = line.split('\t', 10)

        if len(fields) >= 10:
            self.number_of_news = fields[0]
            self.number_of_feed_news = fields[1]
            self.active = fields[2]
            self.breaking_news = fields[3]
            self.url_hash = fields[4]
            self.color = fields[5]
            self.title = html.unescape(fields[6].strip())
            self.title = self.title.replace('\t', ' ')
            self.max_title_length = fields[7]
            self.url = fields[8]
            self.etag = fields[9]
            self.modified = fields[10]

    def __str__(self):
        line = '\t'.join([self.__getattribute__(k) for k in self.__slots__])
        if not line.endswith('\n'):
            line = line + '\n'
        return line


def parse_colors(colors_string):
    """
    Return a list of colors in the format '#XXXXXX' from colors_string or
    the default colors if no color is found.
    """

    # RGB colors
    default_colors = ['#ff0000', '#00ff00', '#0000ff']
    colors = []

    if isinstance(colors_string, str):
        colors = re.findall('#[0-9a-fA-F]{6}', colors_string)

    try:
        assert colors != []
    except AssertionError:
        colors = default_colors

    return colors


def filter_news(feed_entries, last_secs):
    """
    Filter the breaking news, and return its number
    """
    breaking_news_entries = copy.deepcopy(feed_entries)

    if last_secs > 0:
        now = calendar.timegm(time.gmtime())

        for entry in feed_entries:
            published = calendar.timegm(entry.published_parsed)

            if now - last_secs > published:
                breaking_news_entries.remove(entry)

    return breaking_news_entries


def get_news(entry, media_link=False):
    """
    Return media type, date and URL of the news
    """

    media_type = 'text/html'


    if media_link:
        media_types = ['audio', 'video']
    else:
        media_types = ['text']

    entry_link = entry.get('link', '')

    links = entry.get('links', entry_link)

    if hasattr(entry, 'published_parsed'):
        entry_published = str(calendar.timegm(entry.published_parsed))
    else:
        entry_published = 0

    if links != entry_link:
        matching = [link for link in links if link.type.split(
            '/')[0] in media_types]
        if matching:
            media_type = matching[0].type
            entry_link = matching[0].href

    if len(entry_link) == 0:
        entry_link = entry.title_detail.get('href', '')

    title = html.unescape(entry.title)

    if len(title) == 0:
        title = 'ITEM WITHOUT A TITLE'

    return f'{media_type}\t{entry_published}\t{entry_link}\t{title}\n'


def write_news_file(filename, news, media_link):
    """
    Write news to a file in the format:

    media/type\tnews_published_date\tnews_link\tnews_title
    ...
    ...
    """

    with open(filename, 'w', encoding='utf-8') as news_file:
        for entry in news:
            news_file.write(get_news(entry, media_link))


def setup(args):
    """
    Preliminary job...
    """

    if not os.path.isdir(args.data_dir):
        os.mkdir(args.data_dir)


def main(args):
    """
    Entry point...
    """

    # cycle over a colors list (default RGB colors)
    color_cycle = itertools.cycle(parse_colors(args.colors))

    temp_status = tempfile.mkstemp(suffix='.tmp', dir=args.data_dir, text=True)

    if args.last_minutes:
        breaking_news = args.last_minutes * 60
    else:
        breaking_news = 0

    status_fn = os.path.join(args.data_dir, 'status')

    if not os.path.isfile(status_fn):
        print('No status file found!')
        shlex.os.remove(temp_status[1])
        sys.exit(0)

    with open(temp_status[1], 'w', encoding='utf-8') as temp_status_fd, \
            open(status_fn, encoding='utf-8') as status_fd:

        for line in status_fd:
            temp_feed = Feed(line)

            if temp_feed.title.endswith('[NEW FEED]'):
                temp_feed.title = temp_feed.title[0:-10]

            if temp_feed.active == '0' or \
                    (temp_feed.breaking_news == '0' and breaking_news != 0):
                temp_status_fd.write(str(temp_feed))
                continue

            news_filename = os.path.join(args.data_dir, temp_feed.url_hash)

            if os.path.isfile(news_filename):
                etag = temp_feed.etag
                modified = temp_feed.modified
            else:
                etag = ''
                modified = ''

            try:
                feedparser.registerDateHandler(date_handler)
                feed = feedparser.parse(
                    temp_feed.url,
                    etag=etag,
                    modified=modified)
            except (KeyError, AttributeError):  # network error
                temp_status_fd.write(str(temp_feed))
                continue

            feed_status = feed.get('status', 200)  # is a file

            if feed_status == 301:
                temp_feed.url = feed.get('href', temp_feed.url)

            entries = feed.get('entries', [])

            number_of_news = args.number_of_news

            if feed_status == 304:
                if breaking_news:  # no news in the last minutes
                    number_of_news = 0
                    number_of_feed_news = 0
                else:
                    number_of_feed_news = int(temp_feed.number_of_feed_news)
            else:
                if temp_feed.breaking_news == '1':
                    if breaking_news:
                        entries = filter_news(entries, breaking_news)
                    else:
                        entries = []

                number_of_feed_news = len(entries)

                if number_of_feed_news != 0:
                    temp_feed.etag = feed.get('etag', '')
                    temp_feed.modified = feed.get('modified', '')

                try:
                    temp_feed.title = feed.feed.title
                except AttributeError:
                    temp_feed.title = f'{temp_feed.url}'
                finally:
                    if len(temp_feed.title) == 0:
                        temp_feed.title = f'{temp_feed.url}'

                if temp_feed.breaking_news == '1':
                    temp_feed.title = temp_feed.title + ' [BN]'

            if number_of_news == 0 or number_of_news > number_of_feed_news:
                number_of_news = number_of_feed_news

            temp_feed.number_of_news = str(number_of_news)
            temp_feed.number_of_feed_news = str(number_of_feed_news)
            temp_feed.color = next(color_cycle)

            temp_status_fd.write(str(temp_feed))

            if (number_of_news == 0 or feed_status == 304) \
                    and os.path.isfile(news_filename):
                continue

            write_news_file(
                news_filename, entries, args.media_link)

    shlex.os.rename(temp_status[1], status_fn)


if __name__ == '__main__':

    __version__ = '3.0.3'
    feedparser.USER_AGENT = f'PMN/{__version__} ' \
        '+https://github.com/nivit/polybar-module-news'

    arguments = parse_args()

    setup(arguments)

    main(arguments)

# vi:expandtab softtabstop=4 smarttab shiftwidth=4 tabstop=4
