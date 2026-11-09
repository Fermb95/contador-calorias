"""Genera assets/foods_es.json a partir de tool/foods_source.txt."""
import json, sys, pathlib
root = pathlib.Path(__file__).resolve().parent.parent
out = []
names = set()
for ln, line in enumerate((root / 'tool/foods_source.txt').read_text(encoding='utf-8').splitlines(), 1):
    line = line.strip()
    if not line or line.startswith('#'):
        continue
    parts = line.split('|')
    if len(parts) != 9:
        sys.exit(f'línea {ln}: {len(parts)} campos: {line}')
    n, c, k, p, h, g, f, liq, por = parts
    if n in names:
        sys.exit(f'duplicado línea {ln}: {n}')
    names.add(n)
    k, p, h, g, f = map(float, (k, p, h, g, f))
    est = p * 4 + h * 4 + g * 9 + f * 2
    portions = []
    for item in filter(None, por.split(';')):
        pn, pg = item.rsplit(':', 1)
        portions.append([pn, float(pg)])
    out.append({'n': n, 'c': c, 'k': k, 'p': p, 'h': h, 'g': g, 'f': f, 'l': 1 if liq == 'L' else 0, 'u': portions})
    alcohol = c == 'Bebidas' and any(w in n.lower() for w in ('cerveza', 'vino', 'cava', 'sangr', 'vermut', 'destil', 'cubata', 'gin', 'tinto'))
    if k > 20 and not alcohol and abs(est - k) / k > 0.25:
        print(f'AVISO coherencia {n}: kcal {k} vs macros {est:.0f}')
(root / 'assets/foods_es.json').write_text(json.dumps(out, ensure_ascii=False, separators=(',', ':')), encoding='utf-8')
print(len(out), 'alimentos')
