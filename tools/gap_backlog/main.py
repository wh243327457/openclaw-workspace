from __future__ import annotations

import argparse
import json
from pathlib import Path

from .backlog import build_backlog, render_markdown


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description='Generate system gap backlog')
    parser.add_argument('format', choices=['json', 'markdown'], help='output format')
    return parser


def main() -> int:
    args = build_parser().parse_args()
    workspace = Path('/home/node/.openclaw/workspace')
    backlog = build_backlog(workspace)
    if args.format == 'json':
        print(json.dumps(backlog, ensure_ascii=False, indent=2))
        return 0
    print(render_markdown(backlog))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())

