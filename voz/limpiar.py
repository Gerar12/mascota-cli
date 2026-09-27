#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Refina texto para TTS: quita código/rutas/identificadores y lee números en español.

Entra por stdin, sale por stdout. Nunca falla: si algo raro pasa, deja el texto
lo mejor posible. Objetivo: voz natural y limpia, sin tokens imposibles de decir.
"""
import sys, re

try:
    from num2words import num2words
    HAVE_N2W = True
except Exception:
    HAVE_N2W = False


def es_int(n):
    if not HAVE_N2W:
        return str(n)
    try:
        return num2words(int(n), lang="es")
    except Exception:
        return str(n)


def es_num(s):
    """'10,000' -> 'diez mil'; '0.25' -> 'cero punto dos cinco'."""
    s = s.replace(",", "")            # separador de miles
    if not s or s == ".":
        return ""
    if "." in s:
        ip, dec = s.split(".", 1)
        ip = ip or "0"
        head = es_int(ip)
        digs = " ".join(es_int(d) for d in dec if d.isdigit())
        return (head + " punto " + digs).strip() if digs else head
    return es_int(s)


def es_mag(sign, base, suf):
    mult = 1000000 if suf in "Mm" else 1000
    try:
        val = float(base.replace(",", "")) * mult
        words = es_int(val) if val == int(val) else es_num(str(val))
    except Exception:
        words = es_num(base)
    return (("más de " if sign == "+" else "") + words).strip()


UNIT = {
    "ms": "milisegundos", "s": "segundos", "seg": "segundos",
    "min": "minutos", "h": "horas",
    "kb": "kilobytes", "mb": "megabytes", "gb": "gigabytes",
}


def clean(text):
    t = text

    # Markdown del mensaje: omitir bloques, código inline, tablas, URLs y emoji.
    lines = []
    fence = None
    for line in t.splitlines():
        marker = re.match(r"^\s*(`{3,}|~{3,})", line)
        if marker:
            token = marker.group(1)
            if fence is None:
                fence = token
            elif token[0] == fence[0] and len(token) >= len(fence):
                fence = None
            continue
        if fence is None and not re.match(r"^\s*\|", line):
            lines.append(line)
    t = "\n".join(lines)
    t = re.sub(r"(`+).*?\1", " ", t)
    t = re.sub(r"!?\[([^\]]*)\]\([^)]*\)", r"\1", t)
    t = re.sub(r"https?://\S+", " ", t)
    t = re.sub(r"^\s*(?:#+\s*|[-*+]\s+|>\s*)", "", t, flags=re.M)
    t = re.sub(r"[\U0001F000-\U0001FFFF\u2600-\u27BF\u2300-\u23FF\u2B00-\u2BFF\uFE00-\uFE0F]", "", t)

    # --- Quitar tokens técnicos (código, rutas, ids) antes de tocar números ---
    t = re.sub(r"<[^>\n]{1,80}>", " ", t)                      # <tags>
    t = re.sub(r"\$\{?[A-Za-z_]\w*\}?", " ", t)                # $VAR ${VAR}
    t = re.sub(r"\b[\w.\-]+@[\w.\-]+\.\w+\b", " ", t)          # emails
    t = re.sub(r"(?:~|\.{1,2})?/[\w.\-]+(?:/[\w.\-]+)+/?", " ", t)  # rutas /a/b/c
    t = re.sub(r"\b[\w\-]+\.(?:sh|py|js|jsx|ts|tsx|json|md|txt|mp3|aiff|wav|"
               r"log|ya?ml|toml|env|cfg|ini|css|scss|html?|sql|rs|go|rb|java|"
               r"cpp|hpp|xml|csv|pdf|png|jpe?g|svg|lock|key|aiff)\b", " ", t)  # archivo.ext
    t = re.sub(r"\bv?\d+(?:\.\d+){2,}\b", " ", t)              # versiones / IPs 1.2.3
    t = re.sub(r"\b(?=\w*[0-9])(?=\w*[A-Za-z])[A-Za-z0-9]{8,}\b", " ", t)  # hashes/UUIDs/ids
    t = re.sub(r"\b[\w.]+=\S+", " ", t)                        # asignaciones a=b
    t = re.sub(r"\b\w+\(\)", " ", t)                           # func()
    t = re.sub(r"(?<![\w-])--?[A-Za-z][\w-]*", " ", t)         # flags --foo -x
    t = re.sub(r"\b\w*_\w+\b", " ", t)                         # snake_case CONST_CASE
    t = re.sub(r"\b[a-z]+[A-Z]\w*\b", " ", t)                  # camelCase

    # --- Flechas y separadores a pausa hablada ---
    t = re.sub(r"\s*(?:→|⟶|=>|->|←)\s*", " a ", t)

    # --- Números en español ---
    t = re.sub(r"([+]?)(\d[\d,]*(?:\.\d+)?)\s*%",
               lambda m: (("más de " if m.group(1) == "+" else "")
                          + es_num(m.group(2)) + " por ciento"), t)
    t = re.sub(r"#(\d+)", lambda m: "número " + es_int(m.group(1)), t)
    t = re.sub(r"([+]?)(\d[\d,]*(?:\.\d+)?)\s*([MmKk])\b",
               lambda m: es_mag(m.group(1), m.group(2), m.group(3)), t)
    t = re.sub(r"(\d[\d,]*(?:\.\d+)?)\s*(ms|seg|s|min|h|kb|mb|gb)\b",
               lambda m: es_num(m.group(1)) + " " + UNIT[m.group(2).lower()], t)
    t = re.sub(r"([+]?)(\d[\d,]*(?:\.\d+)?)([+]?)",
               lambda m: (("más de " if (m.group(1) == "+" or m.group(3) == "+") else "")
                          + es_num(m.group(2))), t)

    # --- Símbolos que rompen o suenan raro ---
    t = re.sub(r"[`*_~^|\\{}\[\]<>=/#@+]", " ", t)
    t = re.sub(r"\(\s*\)", " ", t)                             # paréntesis vacíos
    t = re.sub(r"[ \t]*&[ \t]*", " y ", t)                     # & -> y

    # --- Normalizar espacios y puntuación ---
    t = re.sub(r"\bmás de(?:\s+más de)+\b", "más de", t)       # "más de más de" -> "más de"
    t = re.sub(r"\s+([,.;:!?])", r"\1", t)                     # espacio antes de signo
    t = re.sub(r"([,.;:])(?=\S)", r"\1 ", t)                   # signo pegado a palabra
    t = re.sub(r"[ \t]+", " ", t)
    t = re.sub(r"\n{2,}", "\n", t)
    t = re.sub(r"^\s*[,.;:]\s*", "", t, flags=re.M)            # línea que abre con signo
    return t.strip()


def main():
    try:
        data = sys.stdin.read()
        try:
            out = clean(data)
        except Exception:
            out = data
        sys.stdout.write(out)
        sys.stdout.flush()
    except Exception:
        # Incluso entrada inválida o un consumidor cerrado deben acabar con exit 0.
        import os
        os._exit(0)


if __name__ == "__main__":
    main()
