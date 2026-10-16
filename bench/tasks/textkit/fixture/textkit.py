"""Small text utilities used by the CLI."""

import re
import unicodedata


def slugify(text, max_len=50):
    """Lowercase ASCII slug with single dashes, trimmed to max_len."""
    text = unicodedata.normalize("NFKD", text).encode("ascii", "ignore").decode()
    text = re.sub(r"[^a-zA-Z0-9]+", "-", text).strip("-").lower()
    return text[:max_len].rstrip("-")


def truncate(text, width, suffix="..."):
    """Cut text to width characters including suffix."""
    if width < len(suffix):
        raise ValueError("width smaller than suffix")
    if len(text) <= width:
        return text
    return text[: width - len(suffix)] + suffix


def word_count(text):
    """Number of whitespace-separated words."""
    return len(text.split())


def title_case(text, small_words=("a", "an", "the", "of", "and", "or", "in")):
    """Title case that keeps small words lowercase except at the start."""
    words = text.lower().split()
    out = []
    for i, w in enumerate(words):
        out.append(w if i > 0 and w in small_words else w.capitalize())
    return " ".join(out)


def parse_duration(value):
    """Parse '1h30m', '45s', '2h' into seconds."""
    match = re.fullmatch(r"(?:(\d+)h)?(?:(\d+)m)?(?:(\d+)s)?", value.strip())
    if not value.strip() or not match:
        raise ValueError(f"invalid duration: {value!r}")
    h, m, s = (int(g) if g else 0 for g in match.groups())
    return h * 3600 + m * 60 + s


def format_bytes(n):
    """Human-readable size using 1024 steps, one decimal."""
    if n < 0:
        raise ValueError("negative size")
    units = ["B", "KB", "MB", "GB", "TB"]
    size = float(n)
    for unit in units:
        if size < 1024 or unit == units[-1]:
            return f"{int(size)} {unit}" if unit == "B" else f"{size:.1f} {unit}"
        size /= 1024


def mask_email(email):
    """Keep first letter and domain: 'john@x.com' -> 'j***@x.com'."""
    if email.count("@") != 1:
        raise ValueError("invalid email")
    user, domain = email.split("@")
    if not user or not domain:
        raise ValueError("invalid email")
    return user[0] + "***@" + domain


def wrap(text, width):
    """Greedy word wrap; words longer than width stay on their own line."""
    lines, current = [], ""
    for word in text.split():
        if not current:
            current = word
        elif len(current) + 1 + len(word) <= width:
            current += " " + word
        else:
            lines.append(current)
            current = word
    if current:
        lines.append(current)
    return lines


def dedupe_preserve(items):
    """Remove duplicates keeping first occurrence order."""
    seen = set()
    return [x for x in items if not (x in seen or seen.add(x))]


def count_vowels(text):
    """Count a, e, i, o, u (case-insensitive, accents stripped)."""
    text = unicodedata.normalize("NFKD", text).lower()
    return sum(1 for c in text if c in "aeiou")
