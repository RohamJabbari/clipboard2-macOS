#!/usr/bin/env python3
"""Adds a release to appcast.xml (the Sparkle update feed Clipboard2 checks every hour).

usage: appcast.py <appcast.xml> <version> <build> <download-url> <sign_update output>
"""
import email.utils
import os
import re
import sys
from xml.sax.saxutils import escape

path, version, build, url, signature = sys.argv[1:6]
match_sig = re.search(r'sparkle:edSignature="([^"]+)"', signature)
match_len = re.search(r'length="(\d+)"', signature)
if not match_sig or not match_len:
    sys.exit(f"Unexpected sign_update output: {signature!r}")

repo = "https://github.com/RohamJabbari/clipboard2-macOS"
item = f"""    <item>
      <title>Version {escape(version)}</title>
      <pubDate>{email.utils.formatdate(usegmt=True)}</pubDate>
      <sparkle:version>{escape(build)}</sparkle:version>
      <sparkle:shortVersionString>{escape(version)}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <sparkle:releaseNotesLink>{repo}/releases/tag/v{escape(version)}</sparkle:releaseNotesLink>
      <enclosure url="{escape(url)}" sparkle:edSignature="{match_sig.group(1)}" length="{match_len.group(1)}" type="application/octet-stream"/>
    </item>
"""

if os.path.exists(path):
    feed = open(path, encoding="utf-8").read()
    if f"<sparkle:version>{build}</sparkle:version>" in feed:
        sys.exit(f"Build {build} is already in {path}")
    marker = "<title>Clipboard2</title>\n"
    feed = feed.replace(marker, marker + item, 1)
else:
    feed = f"""<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Clipboard2</title>
{item}  </channel>
</rss>
"""
open(path, "w", encoding="utf-8").write(feed)
print(f"appcast: added {version} ({build})")
