from __future__ import annotations

import argparse
import json
from pathlib import Path

from .manifest import build_manifest, render_markdown


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description='Generate workspace capability manifest')
    parser.add_argument('format', choices=['json', 'markdown'], help='output format')
    return parser


def main() -> int:
    args = build_parser().parse_args()
    workspace = Path('/home/node/.openclaw/workspace')
    manifest = build_manifest(workspace)
    if args.format == 'json':
        print(json.dumps(manifest, ensure_ascii=False, indent=2))
        return 0
    print(render_markdown(manifest))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())

