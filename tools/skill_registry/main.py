from __future__ import annotations

import argparse
import json
from pathlib import Path

from .registry import build_registry, filter_registry, render_markdown


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description='Generate skill registry')
    parser.add_argument('format', choices=['json', 'markdown'], help='output format')
    parser.add_argument('--tag', help='filter skills by tag')
    parser.add_argument('--trigger', help='filter skills by trigger keyword')
    parser.add_argument('--name', help='filter skills by name keyword')
    return parser


def main() -> int:
    args = build_parser().parse_args()
    workspace = Path('/home/node/.openclaw/workspace')
    registry = build_registry(workspace)
    registry = filter_registry(registry, tag=args.tag, trigger=args.trigger, name=args.name)
    if args.format == 'json':
        print(json.dumps(registry, ensure_ascii=False, indent=2))
        return 0
    print(render_markdown(registry))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
