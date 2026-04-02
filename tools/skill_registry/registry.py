from __future__ import annotations

import re
from pathlib import Path


def _extract_section_lines(text: str, heading: str) -> list[str]:
    lines = text.splitlines()
    captured: list[str] = []
    active = False
    for line in lines:
        if line.strip().startswith(f'## {heading}'):
            active = True
            continue
        if active and line.startswith('## '):
            break
        if active and line.strip().startswith('- '):
            captured.append(line.strip()[2:])
    return captured


def _extract_description(text: str) -> str:
    for line in text.splitlines():
        if line.startswith('description:'):
            return line.split(':', 1)[1].strip()
    return ''


def _extract_frontmatter(text: str) -> dict:
    if not text.startswith('---\n'):
        return {}
    end = text.find('\n---', 4)
    if end == -1:
        return {}
    block = text[4:end]
    data: dict[str, object] = {}
    current_key: str | None = None
    for raw_line in block.splitlines():
        line = raw_line.rstrip()
        if not line.strip():
            continue
        if re.match(r'^[A-Za-z][A-Za-z0-9_-]*:\s*', line):
            key, value = line.split(':', 1)
            current_key = key.strip()
            value = value.strip()
            if value:
                data[current_key] = value
            else:
                data[current_key] = []
            continue
        stripped = line.strip()
        if stripped.startswith('- ') and current_key:
            existing = data.get(current_key)
            if not isinstance(existing, list):
                existing = []
            existing.append(stripped[2:].strip())
            data[current_key] = existing
    return data


def _extract_use_when(description: str) -> list[str]:
    marker = 'Use when '
    if marker not in description:
        return []
    use_text = description.split(marker, 1)[1].strip().rstrip('.')
    return [item.strip() for item in use_text.split(',') if item.strip()]


def _extract_inline_section_sentences(text: str, heading: str) -> list[str]:
    lines = text.splitlines()
    captured: list[str] = []
    active = False
    for line in lines:
        if line.strip().startswith(f'## {heading}'):
            active = True
            continue
        if active and line.startswith('## '):
            break
        if active:
            stripped = line.strip()
            if stripped and not stripped.startswith('- ') and not stripped.startswith('```'):
                captured.append(stripped)
    return captured


def _extract_expected_files(text: str) -> list[str]:
    lines = text.splitlines()
    files: list[str] = []
    for line in lines:
        stripped = line.strip()
        if stripped.startswith('- `') and '`' in stripped[3:]:
            candidate = stripped.split('`')[1]
            if '/' in candidate or candidate.endswith('.md') or candidate.endswith('/'):
                files.append(candidate)
    return files


def _infer_tags(name: str, description: str) -> list[str]:
    text = f'{name} {description}'.lower()
    tags: list[str] = []
    for tag, keywords in {
        'memory': ['memory', '记忆'],
        'skills': ['skill', '技能'],
        'bootstrap': ['bootstrap', '初始化', 'onboarding'],
        'sync': ['sync', '同步', 'repository', '仓库'],
        'review': ['review', '审查', 'proposal'],
        'tenant': ['tenant', '子系统', '微信'],
        'team': ['agent team', '多角色', 'main-assistant'],
    }.items():
        if any(keyword in text for keyword in keywords):
            tags.append(tag)
    return tags


def _infer_risk_level(rules: list[str], description: str) -> str:
    text = ' '.join(rules) + ' ' + description.lower()
    if 'external' in text or '敏感' in text or 'secret' in text or 'shared' in text:
        return 'medium'
    if rules:
        return 'low-medium'
    return 'low'


def _skill_record(skill_file: Path, source: str, workspace: Path) -> dict:
    text = skill_file.read_text(encoding='utf-8')
    frontmatter = _extract_frontmatter(text)
    description = str(frontmatter.get('description') or _extract_description(text))
    rules = _extract_section_lines(text, 'Decision rule') + _extract_section_lines(text, 'Safety boundaries')
    frontmatter_tags = frontmatter.get('tags') if isinstance(frontmatter.get('tags'), list) else []
    frontmatter_use_when = frontmatter.get('triggers') if isinstance(frontmatter.get('triggers'), list) else []
    frontmatter_inputs = frontmatter.get('inputs') if isinstance(frontmatter.get('inputs'), list) else []
    frontmatter_outputs = frontmatter.get('outputs') if isinstance(frontmatter.get('outputs'), list) else []
    frontmatter_risks = frontmatter.get('risks') if isinstance(frontmatter.get('risks'), list) else []
    return {
        'name': skill_file.parent.name,
        'path': str(skill_file.relative_to(workspace)),
        'source': source,
        'description': description,
        'useWhen': frontmatter_use_when or _extract_use_when(description),
        'components': _extract_section_lines(text, 'Components'),
        'responsibilities': _extract_section_lines(text, 'Responsibilities'),
        'goals': _extract_section_lines(text, 'Goals'),
        'inputs': frontmatter_inputs,
        'expectedFiles': frontmatter_outputs or _extract_expected_files(text),
        'operatorNotes': _extract_inline_section_sentences(text, 'Operator flow'),
        'rules': rules,
        'risks': frontmatter_risks,
        'tags': frontmatter_tags or _infer_tags(skill_file.parent.name, description),
        'riskLevel': _infer_risk_level(frontmatter_risks or rules, description),
    }


def build_registry(workspace: Path) -> dict:
    workspace_skill_files = sorted((workspace / 'skills').glob('*/SKILL.md'))
    exported_skill_files = sorted((workspace / 'exports' / 'openclaw-skills' / 'skills').glob('*/SKILL.md'))
    skills = [
        *[_skill_record(path, 'workspace', workspace) for path in workspace_skill_files],
        *[_skill_record(path, 'exported', workspace) for path in exported_skill_files],
    ]
    return {
        'workspace': str(workspace),
        'skillCount': len(skills),
        'skills': skills,
    }


def filter_registry(registry: dict, tag: str | None = None, trigger: str | None = None, name: str | None = None) -> dict:
    skills = registry['skills']
    if tag:
        tag_lower = tag.lower()
        skills = [skill for skill in skills if any(item.lower() == tag_lower for item in skill.get('tags', []))]
    if trigger:
        trigger_lower = trigger.lower()
        skills = [
            skill for skill in skills
            if any(trigger_lower in item.lower() for item in skill.get('useWhen', []))
        ]
    if name:
        name_lower = name.lower()
        skills = [skill for skill in skills if name_lower in skill.get('name', '').lower()]
    return {
        **registry,
        'skillCount': len(skills),
        'skills': skills,
    }


def render_markdown(registry: dict) -> str:
    lines = [
        '# Skill Registry',
        '',
        f"- Workspace: `{registry['workspace']}`",
        f"- Skill count: `{registry['skillCount']}`",
        '',
    ]
    for skill in registry['skills']:
        lines.append(f"## `{skill['name']}`")
        lines.append(f"- Source: `{skill['source']}`")
        lines.append(f"- Path: `{skill['path']}`")
        if skill['description']:
            lines.append(f"- Description: {skill['description']}")
        if skill['tags']:
            lines.append(f"- Tags: {', '.join(skill['tags'])}")
        if skill['riskLevel']:
            lines.append(f"- Risk level: `{skill['riskLevel']}`")
        if skill['useWhen']:
            lines.append(f"- Use when: {'; '.join(skill['useWhen'])}")
        if skill['inputs']:
            lines.append(f"- Inputs: {'; '.join(skill['inputs'])}")
        if skill['goals']:
            lines.append(f"- Goals: {'; '.join(skill['goals'])}")
        if skill['components']:
            lines.append(f"- Components: {'; '.join(skill['components'])}")
        if skill['responsibilities']:
            lines.append(f"- Responsibilities: {'; '.join(skill['responsibilities'])}")
        if skill['expectedFiles']:
            lines.append(f"- Expected files: {'; '.join(skill['expectedFiles'])}")
        if skill['operatorNotes']:
            lines.append(f"- Operator notes: {'; '.join(skill['operatorNotes'])}")
        if skill['risks']:
            lines.append(f"- Risks: {'; '.join(skill['risks'])}")
        if skill['rules']:
            lines.append(f"- Rules: {'; '.join(skill['rules'])}")
        lines.append('')
    return '\n'.join(lines).rstrip()
