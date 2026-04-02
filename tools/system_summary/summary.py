from __future__ import annotations

import json
import subprocess
from datetime import datetime, timezone
from pathlib import Path


def _run(command: str) -> str:
    result = subprocess.run(command, shell=True, capture_output=True, text=True)
    return (result.stdout or '').strip()


def _list_memory_days(memory_dir: Path) -> list[str]:
    if not memory_dir.exists():
        return []
    return sorted([path.name for path in memory_dir.glob('*.md')])


def _tenant_count(workspace: Path) -> int:
    registry = workspace / 'tenants' / 'registry.json'
    if not registry.exists():
        return 0
    data = json.loads(registry.read_text(encoding='utf-8'))
    return len(data.get('tenants', {}))


def build_summary(workspace: Path) -> dict:
    capability_raw = _run('python3 -m tools.capability_manifest.main json')
    capability = json.loads(capability_raw) if capability_raw else {}

    memory_days = _list_memory_days(workspace / 'memory')
    heartbeat_exists = (workspace / 'HEARTBEAT.md').exists()
    ui_8090 = bool(_run("lsof -nP -iTCP:8090 -sTCP:LISTEN 2>/dev/null | tail -n +2"))
    ui_8091 = bool(_run("lsof -nP -iTCP:8091 -sTCP:LISTEN 2>/dev/null | tail -n +2"))

    return {
        'generatedAt': datetime.now(timezone.utc).isoformat(),
        'workspace': str(workspace),
        'defaultAgent': capability.get('defaultAgent'),
        'agentCount': len(capability.get('agents', [])),
        'modelCount': len(capability.get('models', [])),
        'skillCount': len(capability.get('skills', [])),
        'tenantCount': _tenant_count(workspace),
        'memoryDayCount': len(memory_days),
        'memoryDays': memory_days[-7:],
        'heartbeatConfigured': heartbeat_exists,
        'ui': {
            'port8090Listening': ui_8090,
            'port8091Listening': ui_8091,
        },
    }


def render_markdown(summary: dict) -> str:
    ui = summary['ui']
    lines = [
        '# System Summary',
        '',
        f"- Generated at: `{summary['generatedAt']}`",
        f"- Workspace: `{summary['workspace']}`",
        f"- Default agent: `{summary['defaultAgent']}`",
        f"- Agents: `{summary['agentCount']}`",
        f"- Models: `{summary['modelCount']}`",
        f"- Skills: `{summary['skillCount']}`",
        f"- Tenants: `{summary['tenantCount']}`",
        f"- Memory days: `{summary['memoryDayCount']}`",
        f"- Heartbeat file present: `{summary['heartbeatConfigured']}`",
        f"- UI 8090 listening: `{ui['port8090Listening']}`",
        f"- Health 8091 listening: `{ui['port8091Listening']}`",
    ]
    if summary['memoryDays']:
        lines.append(f"- Recent memory days: `{', '.join(summary['memoryDays'])}`")
    return '\n'.join(lines)
