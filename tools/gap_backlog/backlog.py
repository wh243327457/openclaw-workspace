from __future__ import annotations

from pathlib import Path


DEFAULT_GAPS = [
    {
        'id': 'ppt-generation-pipeline',
        'title': 'PPT 生成流程还未产品化',
        'priority': 'high',
        'status': 'open',
        'area': 'content',
        'summary': '目前能生成 PPT，但还依赖临时脚本和人工迭代。',
        'nextAction': '沉淀模板、版式规则和导出流程，做成稳定工具。',
    },
    {
        'id': 'media-delivery',
        'title': '媒体文件回传链路不完整',
        'priority': 'high',
        'status': 'open',
        'area': 'messaging',
        'summary': '本地能生成文件，但跨聊天面直接发送附件能力受限。',
        'nextAction': '补统一媒体发送策略和平台差异处理。',
    },
    {
        'id': 'model-switch-policy',
        'title': '模型切换策略缺少统一探测和回退层',
        'priority': 'high',
        'status': 'partial',
        'area': 'models',
        'summary': '已经有配置和人工排查，但缺少稳定的自动探测、切换和解释输出。',
        'nextAction': '做标准化模型探活、回退和对用户解释的封装。',
    },
    {
        'id': 'lan-ui-observability',
        'title': '局域网 UI 可达性缺少持续观测',
        'priority': 'medium',
        'status': 'open',
        'area': 'ops',
        'summary': '8090/8091 是否监听目前靠临时排查，缺少持续状态面板。',
        'nextAction': '把 UI/health 端口与来源限制整合进 system summary。',
    },
    {
        'id': 'skill-metadata-normalization',
        'title': '技能元数据还不统一',
        'priority': 'medium',
        'status': 'open',
        'area': 'skills',
        'summary': '不同技能的 SKILL.md 结构不完全一致，注册表抽取深度有限。',
        'nextAction': '统一 SKILL.md 约定字段，补标签、输入输出、风险等级。',
    },
]


def build_backlog(workspace: Path) -> dict:
    return {
        'workspace': str(workspace),
        'gapCount': len(DEFAULT_GAPS),
        'gaps': DEFAULT_GAPS,
    }


def render_markdown(backlog: dict) -> str:
    lines = [
        '# Gap Backlog',
        '',
        f"- Workspace: `{backlog['workspace']}`",
        f"- Gap count: `{backlog['gapCount']}`",
        '',
    ]
    for gap in backlog['gaps']:
        lines.extend([
            f"## `{gap['id']}`",
            f"- Title: {gap['title']}",
            f"- Priority: `{gap['priority']}`",
            f"- Status: `{gap['status']}`",
            f"- Area: `{gap['area']}`",
            f"- Summary: {gap['summary']}",
            f"- Next action: {gap['nextAction']}",
            '',
        ])
    return '\n'.join(lines).rstrip()
