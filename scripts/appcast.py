#!/usr/bin/env python3
import os
from pathlib import Path
from email.utils import formatdate
import xml.etree.ElementTree as ET

version = os.environ['LIGHT_VERSION']
dist = Path(os.environ['LIGHT_DIST'])
namespace = 'http://www.andymatuschak.org/xml-namespaces/sparkle'
ET.register_namespace('sparkle', namespace)
rss = ET.Element('rss', version='2.0')
channel = ET.SubElement(rss, 'channel')
ET.SubElement(channel, 'title').text = 'Light Updates'
item = ET.SubElement(channel, 'item')
ET.SubElement(item, 'title').text = f'Light {version}'
ET.SubElement(item, 'pubDate').text = formatdate(usegmt=True)
for key, value in [('version', version), ('shortVersionString', version), ('minimumSystemVersion', '13.0')]:
    ET.SubElement(item, f'{{{namespace}}}{key}').text = value
ET.SubElement(item, 'enclosure', {
    'url': f'https://github.com/metalnakls/light/releases/download/v{version}/Light.zip',
    'type': 'application/octet-stream',
    'length': str((dist / 'Light.zip').stat().st_size),
    f'{{{namespace}}}edSignature': os.environ['LIGHT_SIGNATURE'],
})
ET.indent(rss)
ET.ElementTree(rss).write(dist / 'appcast.xml', encoding='utf-8', xml_declaration=True)
