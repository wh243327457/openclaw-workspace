from __future__ import annotations

import json
from pathlib import Path


def _read_skill(skill_file: Path) -> dict:
    text = skill_file.read_text(encoding='utf-8')
    name = skill_file.parent.name
    description = ''
    for line in text.splitlines():
        if line.startswith('description:'):
            description = line.split(':', 1)[1].strip()
            break
    return {
        'name': name,
        'path': str(skill_file.relative_to(skill_file.parents[3] if 'exports/openclaw-skills' in str(skill_file) else skill_file.parents[2])),
        'description': description,
        'source': 'exported' if 'exports/openclaw-skills' in str(skill_file) else 'workspace',
    }


def build_manifest(workspace: Path) -> dict:
    config_path = workspace / 'agent-team' / 'config.json'
    config = json.loads(config_path.read_text(encoding='utf-8'))

    skill_files = sorted((workspace / 'skills').glob('*/SKILL.md'))
    exported_skill_files = sorted((workspace / 'exports' / 'openclaw-skills' / 'skills').glob('*/SKILL.md'))
    skills = [_read_skill(path) for path in [*skill_files, *exported_skill_files]]

    return {
        'workspace': str(workspace),
        'version': config.get('version'),
        'defaultAgent': config.get('defaultAgent'),
        'agents': [
            {
                'id': agent_id,
                'label': agent.get('label'),
                'role': agent.get('role'),
                'defaultModel': agent.get('defaultModel'),
                'userFacing': agent.get('userFacing', False),
                'fallbackModels': agent.get('fallbackModels', []),
            }
            for agent_id, agent in config.get('agents', {}).items()
        ],
        'models': [
            {
                'label': model.get('label'),
                'provider': model.get('provider'),
                'modelName': model.get('modelName'),
                'costTier': model.get('costTier'),
                'tags': model.get('tags', []),
            }
            for model in config.get('models', [])
        ],
        'skills': skills,
    }


def render_markdown(manifest: dict) -> str:
    lines = [
        '# Capability Manifest',
        '',
        f"- Workspace: `{manifest['workspace']}`",
        f"- Config version: `{manifest['version']}`",
        f"- Default agent: `{manifest['defaultAgent']}`",
        f"- Agent count: `{len(manifest['agents'])}`",
        f"- Model count: `{len(manifest['models'])}`",
        f"- Skill count: `{len(manifest['skills'])}`",
        '',
        '## Agents',
    ]
    for agent in manifest['agents']:
        lines.append(
            f"- `{agent['id']}` · {agent['label']} · role={agent['role']} · model={agent['defaultModel']}"
        )
    lines.append('')
    lines.append('## Models')
    for model in manifest['models']:
        lines.append(
            f"- `{model['modelName']}` · {model['label']} · provider={model['provider']} · tier={model['costTier']}"
        )
    lines.append('')
    lines.append('## Skills')
    for skill in manifest['skills']:
        lines.append(
            f"- `{skill['name']}` · source={skill['source']} · {skill['description']}"
        )
    return '\n'.join(lines)
