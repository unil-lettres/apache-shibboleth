#!/usr/bin/env python3
"""
Extract available Shibboleth attributes by cross-referencing metadata.xml and attribute-map.xml
"""

import sys
import xml.etree.ElementTree as ET
from urllib.request import urlopen, Request
from urllib.error import URLError, HTTPError


def parse_attribute_map(attribute_map_path):
    """Parse attribute-map.xml and create OID to id mapping"""
    NS = {'attr': 'urn:mace:shibboleth:2.0:attribute-map'}
    
    try:
        tree = ET.parse(attribute_map_path)
        root = tree.getroot()
        
        oid_to_id = {}
        for attr in root.findall('.//attr:Attribute', NS):
            oid = attr.get('name')
            attr_id = attr.get('id')
            if oid and attr_id:
                oid_to_id[oid] = attr_id
        
        return oid_to_id
    except Exception as e:
        print(f"ERROR: Failed to parse attribute-map.xml: {e}", file=sys.stderr)
        return {}


def fetch_metadata(resource_id):
    """Fetch metadata XML from AAI Resource Registry"""
    url = f"https://rr.aai.switch.ch/entity/resource/{resource_id}/metadata.xml"
    
    try:
        req = Request(url, headers={'User-Agent': 'Apache-Shibboleth-Docker/1.0'})
        with urlopen(req, timeout=10) as response:
            return response.read()
    except HTTPError as e:
        print(f"ERROR: HTTP {e.code} when fetching metadata from {url}", file=sys.stderr)
        return None
    except URLError as e:
        print(f"ERROR: Failed to fetch metadata: {e.reason}", file=sys.stderr)
        return None
    except Exception as e:
        print(f"ERROR: Unexpected error fetching metadata: {e}", file=sys.stderr)
        return None


def parse_metadata(xml_content):
    """Parse metadata XML and extract RequestedAttribute OIDs"""
    NS = {'md': 'urn:oasis:names:tc:SAML:2.0:metadata'}
    
    try:
        root = ET.fromstring(xml_content)
        
        requested_oids = []
        # Find all RequestedAttribute elements
        for req_attr in root.findall('.//md:RequestedAttribute', NS):
            oid = req_attr.get('Name')
            friendly_name = req_attr.get('FriendlyName', '')
            
            if oid:
                requested_oids.append({
                    'oid': oid,
                    'friendly': friendly_name
                })
        
        return requested_oids
    except Exception as e:
        print(f"ERROR: Failed to parse metadata XML: {e}", file=sys.stderr)
        return []


def main():
    if len(sys.argv) < 3:
        print("Usage: extract_attributes.py <resource_id> <attribute_map_path>", file=sys.stderr)
        sys.exit(1)
    
    resource_id = sys.argv[1]
    attribute_map_path = sys.argv[2]
    
    # Parse attribute-map.xml
    oid_to_id = parse_attribute_map(attribute_map_path)
    if not oid_to_id:
        print("ERROR: No attributes found in attribute-map.xml", file=sys.stderr)
        sys.exit(1)
    
    # Fetch and parse metadata
    metadata_xml = fetch_metadata(resource_id)
    if not metadata_xml:
        sys.exit(1)
    
    requested_attrs = parse_metadata(metadata_xml)
    if not requested_attrs:
        print("ERROR: No RequestedAttribute found in metadata", file=sys.stderr)
        sys.exit(1)
    
    # Cross-reference: find attribute IDs that are both requested and mapped
    available_ids = []
    
    for attr in requested_attrs:
        oid = attr['oid']
        if oid in oid_to_id:
            available_ids.append(oid_to_id[oid])
    
    # Output: comma-separated list to stdout (or nothing if empty)
    if available_ids:
        print(','.join(available_ids))


if __name__ == '__main__':
    main()
