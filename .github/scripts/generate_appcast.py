#!/usr/bin/env python3
"""
Generate appcast.json from GitHub Releases
Automatically fetches release information and converts markdown to HTML
"""

import json
import os
import sys
import re
from datetime import datetime
from typing import Dict, List, Optional
import urllib.request
import urllib.error

def fetch_github_releases(repo: str, token: Optional[str] = None) -> List[Dict]:
    """Fetch releases from GitHub API"""
    url = f"https://api.github.com/repos/{repo}/releases"
    headers = {
        'Accept': 'application/vnd.github.v3+json',
        'User-Agent': 'XKey-Appcast-Generator'
    }
    
    if token:
        headers['Authorization'] = f'token {token}'
    
    req = urllib.request.Request(url, headers=headers)
    
    try:
        with urllib.request.urlopen(req) as response:
            return json.loads(response.read().decode())
    except urllib.error.HTTPError as e:
        print(f"Error fetching releases: {e}", file=sys.stderr)
        sys.exit(1)

def markdown_to_html(markdown: str) -> str:
    """Convert markdown to HTML (simple implementation)"""
    html = markdown
    
    # Headers
    html = re.sub(r'^### (.*?)$', r'<h3>\1</h3>', html, flags=re.MULTILINE)
    html = re.sub(r'^## (.*?)$', r'<h2>\1</h2>', html, flags=re.MULTILINE)
    html = re.sub(r'^# (.*?)$', r'<h1>\1</h1>', html, flags=re.MULTILINE)
    
    # Bold and italic
    html = re.sub(r'\*\*\*(.+?)\*\*\*', r'<strong><em>\1</em></strong>', html)
    html = re.sub(r'\*\*(.+?)\*\*', r'<strong>\1</strong>', html)
    html = re.sub(r'\*(.+?)\*', r'<em>\1</em>', html)
    html = re.sub(r'__(.+?)__', r'<strong>\1</strong>', html)
    html = re.sub(r'_(.+?)_', r'<em>\1</em>', html)
    
    # Links
    html = re.sub(r'\[(.+?)\]\((.+?)\)', r'<a href="\2">\1</a>', html)
    
    # Code blocks
    html = re.sub(r'```[\w]*\n(.*?)\n```', r'<pre><code>\1</code></pre>', html, flags=re.DOTALL)
    html = re.sub(r'`(.+?)`', r'<code>\1</code>', html)
    
    # Lists
    lines = html.split('\n')
    in_ul = False
    in_ol = False
    result = []
    
    for line in lines:
        # Unordered list
        if re.match(r'^[\*\-\+] ', line):
            if not in_ul:
                result.append('<ul>')
                in_ul = True
            result.append(f'<li>{line[2:].strip()}</li>')
        # Ordered list
        elif re.match(r'^\d+\. ', line):
            if not in_ol:
                result.append('<ol>')
                in_ol = True
            cleaned_line = re.sub(r'^\d+\. ', '', line).strip()
            result.append(f'<li>{cleaned_line}</li>')
        else:
            if in_ul:
                result.append('</ul>')
                in_ul = False
            if in_ol:
                result.append('</ol>')
                in_ol = False
            if line.strip():
                result.append(f'<p>{line}</p>')
    
    if in_ul:
        result.append('</ul>')
    if in_ol:
        result.append('</ol>')
    
    return '\n'.join(result)

def find_dmg_asset(assets: List[Dict]) -> Optional[Dict]:
    """Find the main DMG file in release assets"""
    # Look for XKey.dmg first
    for asset in assets:
        if asset['name'] == 'XKey.dmg':
            return asset
    
    # Fallback to any .dmg file
    for asset in assets:
        if asset['name'].endswith('.dmg') and 'IM' not in asset['name']:
            return asset
    
    return None

def generate_appcast_item(release: Dict) -> Optional[Dict]:
    """Generate a single appcast item from a GitHub release"""
    # Skip drafts and pre-releases
    if release.get('draft') or release.get('prerelease'):
        return None
    
    # Find DMG asset
    dmg_asset = find_dmg_asset(release.get('assets', []))
    if not dmg_asset:
        print(f"Warning: No DMG found for release {release['tag_name']}", file=sys.stderr)
        return None
    
    # Extract version from tag (remove 'v' prefix if present)
    version = release['tag_name'].lstrip('v')
    
    # Convert release notes markdown to HTML
    release_notes = release.get('body', '')
    release_notes_html = markdown_to_html(release_notes) if release_notes else ''
    
    # Add link to full release notes
    release_url = release['html_url']
    if release_notes_html:
        release_notes_html += f'\n<p><a href="{release_url}">Xem chi tiết trên GitHub</a></p>'
    
    # Parse published date
    pub_date = release.get('published_at', release.get('created_at'))
    
    item = {
        'title': f"Version {version}",
        'version': version,
        'url': release_url,
        'releaseNotesHTML': release_notes_html,
        'pubDate': pub_date,
        'minimumSystemVersion': '12.0',
        'enclosure': {
            'url': dmg_asset['browser_download_url'],
            'version': version,
            'length': dmg_asset['size'],
            'type': 'application/octet-stream'
        }
    }
    
    # Note: edSignature needs to be added manually or via build script
    # We'll keep existing signatures if updating
    
    return item

def generate_appcast(repo: str, token: Optional[str] = None, existing_appcast: Optional[Dict] = None) -> Dict:
    """Generate complete appcast.json from GitHub releases"""
    releases = fetch_github_releases(repo, token)
    
    # Create signature map from existing appcast
    signature_map = {}
    if existing_appcast and 'items' in existing_appcast:
        for item in existing_appcast['items']:
            if 'enclosure' in item and 'edSignature' in item['enclosure']:
                signature_map[item['version']] = item['enclosure']['edSignature']
    
    items = []
    for release in releases:
        item = generate_appcast_item(release)
        if item:
            # Restore signature if exists
            version = item['version']
            if version in signature_map:
                item['enclosure']['edSignature'] = signature_map[version]
            items.append(item)
    
    # Sort by version (newest first)
    items.sort(key=lambda x: x['pubDate'], reverse=True)
    
    # Only keep the latest release
    if items:
        items = [items[0]]
    
    appcast = {
        'title': 'XKey Updates',
        'description': 'XKey - Vietnamese Input Method for macOS',
        'language': 'vi',
        'items': items
    }
    
    return appcast

def main():
    # Get repository from environment or argument
    repo = os.getenv('GITHUB_REPOSITORY', 'xmannv/xkey')
    token = os.getenv('GITHUB_TOKEN')
    
    # Load existing appcast to preserve signatures
    existing_appcast = None
    appcast_path = 'appcast.json'
    if os.path.exists(appcast_path):
        try:
            with open(appcast_path, 'r', encoding='utf-8') as f:
                existing_appcast = json.load(f)
        except Exception as e:
            print(f"Warning: Could not load existing appcast: {e}", file=sys.stderr)
    
    # Generate new appcast
    appcast = generate_appcast(repo, token, existing_appcast)
    
    # Write to file
    output_path = os.getenv('OUTPUT_PATH', 'appcast.json')
    with open(output_path, 'w', encoding='utf-8') as f:
        json.dump(appcast, f, indent=2, ensure_ascii=False)
    
    print(f"✅ Generated appcast with {len(appcast['items'])} releases")
    print(f"📝 Output: {output_path}")

if __name__ == '__main__':
    main()
