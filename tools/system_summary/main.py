from __future__ import annotations

import argparse
import json
from pathlib import Path

from .summary import build_summary, render_markdown


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description='Generate workspace system summary')
    parser.add_argument('format', choices=['json', 'markdown'], help='output format')
    return parser


def main() -> int:
    args = build_parser().parse_args()
    workspace = Path('/home/node/.openclaw/workspace')
    summary = build_summary(workspace)
    if args.format == 'json':
      print(json.dumps(summary, ensure_ascii=False, indent=2))
      return 0
    print(render_markdown(summary))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())

