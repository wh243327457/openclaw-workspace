from __future__ import annotations

import argparse
import json

from .proxy_web_fetch import extract_markdown_like, extract_text, fetch_url, normalize_url


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description='Fetch a webpage through the local proxy and extract readable text')
    parser.add_argument('url', help='target URL')
    parser.add_argument('--format', choices=['text', 'markdown', 'json'], default='markdown')
    parser.add_argument('--max-chars', type=int, default=5000)
    return parser


def main() -> int:
    args = build_parser().parse_args()
    url = normalize_url(args.url)
    content_type, html_text = fetch_url(url)
    if args.format == 'text':
        extracted = extract_text(html_text)
        print(extracted[: args.max_chars])
        return 0
    if args.format == 'markdown':
        extracted = extract_markdown_like(html_text)
        print(extracted[: args.max_chars])
        return 0

    extracted = extract_markdown_like(html_text)
    print(json.dumps({
        'url': url,
        'contentType': content_type,
        'content': extracted[: args.max_chars],
    }, ensure_ascii=False, indent=2))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
