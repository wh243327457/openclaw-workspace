from __future__ import annotations

import html
import os
import re
import urllib.parse
import urllib.request
from html.parser import HTMLParser


class _TextExtractor(HTMLParser):
    def __init__(self) -> None:
        super().__init__()
        self._chunks: list[str] = []
        self._skip_stack: list[str] = []

    def handle_starttag(self, tag: str, attrs) -> None:
        if tag in {"script", "style", "noscript"}:
            self._skip_stack.append(tag)
        elif not self._skip_stack and tag in {"p", "div", "br", "li", "section", "article", "h1", "h2", "h3", "h4", "h5", "h6"}:
            self._chunks.append("\n")

    def handle_endtag(self, tag: str) -> None:
        if self._skip_stack and self._skip_stack[-1] == tag:
            self._skip_stack.pop()
        elif not self._skip_stack and tag in {"p", "div", "li", "section", "article"}:
            self._chunks.append("\n")

    def handle_data(self, data: str) -> None:
        if self._skip_stack:
            return
        text = data.strip()
        if text:
            self._chunks.append(text)
            self._chunks.append(" ")

    def get_text(self) -> str:
        text = "".join(self._chunks)
        text = html.unescape(text)
        text = re.sub(r"\r", "", text)
        text = re.sub(r"[ \t]+", " ", text)
        text = re.sub(r"\n{3,}", "\n\n", text)
        return text.strip()


def fetch_url(url: str, timeout: int = 20) -> tuple[str, str]:
    proxy = os.environ.get("HTTPS_PROXY") or os.environ.get("https_proxy") or os.environ.get("HTTP_PROXY") or os.environ.get("http_proxy")
    handlers = []
    if proxy:
        handlers.append(urllib.request.ProxyHandler({"http": proxy, "https": proxy}))
    opener = urllib.request.build_opener(*handlers)
    request = urllib.request.Request(
        url,
        headers={
            "User-Agent": "Mozilla/5.0 (OpenClaw local fetch helper)",
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
        },
    )
    with opener.open(request, timeout=timeout) as response:
        raw = response.read()
        charset = response.headers.get_content_charset() or "utf-8"
        content_type = response.headers.get_content_type()
        text = raw.decode(charset, errors="replace")
    return content_type, text


def extract_text(html_text: str) -> str:
    parser = _TextExtractor()
    parser.feed(html_text)
    text = parser.get_text()
    return text


def extract_markdown_like(html_text: str) -> str:
    text = extract_text(html_text)
    lines = [line.strip() for line in text.splitlines()]
    cleaned = []
    for line in lines:
        if not line:
            if cleaned and cleaned[-1] != "":
                cleaned.append("")
            continue
        cleaned.append(line)
    return "\n".join(cleaned).strip()


def normalize_url(url: str) -> str:
    parsed = urllib.parse.urlparse(url)
    if not parsed.scheme:
        return "https://" + url
    return url
