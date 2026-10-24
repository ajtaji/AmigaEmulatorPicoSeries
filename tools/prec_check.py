"""Find expressions that PureMetal and PureBasic group differently.

    py -3 tools/prec_check.py <file>...

PureMetal's operator precedence is C-like by ruling (ParserCore.pbi
GetPrecedence, frozen 2026-07-29): shifts bind LOOSER than + -, and % & | !
share the level of * /. PureBasic ranks << >> % ! highest, then | &, then * /,
then + -. The shared chip sources (amiga/*.pmi) are compiled by both, and the
generator writes the same expressions for both, so an unparenthesised mix is
a different program on the Pico than on the PC - `pc + ((vs) << 24) >> 24`
sign-extends on the PC and shifts the whole sum on the Pico.

Each expression is parsed under both tables; any line whose two trees differ
is printed. Exit 1 when one is found.
"""
import re, sys

PB = {'<<': 7, '>>': 7, '%': 7, '!': 7, '|': 6, '&': 6, '*': 5, '/': 5, '+': 4, '-': 4,
      '=': 3, '<>': 3, '<': 3, '>': 3, '<=': 3, '>=': 3, 'and': 1, 'or': 1, 'xor': 1}
PM = {'<<': 4, '>>': 4, '%': 6, '!': 6, '|': 6, '&': 6, '*': 6, '/': 6, '+': 5, '-': 5,
      '=': 3, '<>': 3, '<': 3, '>': 3, '<=': 3, '>=': 3, 'and': 1, 'or': 1, 'xor': 1}

TOK = re.compile(r'\s*(?:(\$[0-9A-Fa-f]+|%[01]+(?![\w])|\d+(?:\.\d+)?)|([#@*]?[A-Za-z_][\w.]*\$?)|'
                 r'(<>|<=|>=|<<|>>|[-+*/%&|!~=<>(),\\])|("[^"]*"))')

class Bad(Exception):
    pass

def tokens(s):
    out, i = [], 0
    while i < len(s):
        m = TOK.match(s, i)
        if not m or m.end() == i:
            if s[i:].strip() == '':
                break
            raise Bad(s[i:])
        i = m.end()
        num, name, op, st = m.groups()
        if num or st:
            out.append(('v', num or st))
        elif name:
            low = name.lower()
            if low in ('and', 'or', 'xor'):
                out.append(('op', low))
            elif low == 'not':
                out.append(('not', low))
            else:
                out.append(('n', name))
        else:
            out.append(('op', op) if op not in '(),' else (op, op))
    return out

def parse(toks, table):
    pos = [0]

    def peek():
        return toks[pos[0]] if pos[0] < len(toks) else ('end', '')

    def take():
        t = peek()
        pos[0] += 1
        return t

    def primary():
        t = take()
        if t[0] == 'op' and t[1] in ('-', '~', '!'):
            return ('u' + t[1], primary())
        if t[0] == 'not':
            return ('not', expr(2))
        if t[0] == '(':
            v = expr(0)
            if take()[0] != ')':
                raise Bad('paren')
            return v
        if t[0] == 'v':
            return t[1]
        if t[0] == 'n':
            name = t[1]
            if peek()[0] == '(':
                take()
                args = []
                if peek()[0] != ')':
                    while True:
                        args.append(expr(0))
                        if peek()[0] == ',':
                            take()
                            continue
                        break
                if take()[0] != ')':
                    raise Bad('call')
                node = ('call', name, tuple(args))
            else:
                node = name
            while peek() == ('op', '\\'):
                take()
                node = ('field', node, take()[1])
            return node
        raise Bad(str(t))

    def expr(minp):
        left = primary()
        while True:
            t = peek()
            if t[0] != 'op' or t[1] not in table:
                return left
            p = table[t[1]]
            if p <= minp:
                return left
            take()
            right = expr(p)
            left = (t[1], left, right)

    v = expr(0)
    if pos[0] != len(toks):
        raise Bad('trailing ' + str(toks[pos[0]:]))
    return v

HEAD = re.compile(r'^\s*(?:If|ElseIf|While|Until|ProcedureReturn|Case)\b(.*)$', re.I)
ASSIGN = re.compile(r'^\s*[A-Za-z_*][\w.\\()+\-* ]*?\s*=(?!=)(.*)$')

def exprs_of(line):
    code = line.split(';', 1)[0].rstrip()
    if not code.strip() or code.lstrip().startswith(('!', 'ASM', 'Macro', 'EndMacro')):
        return []
    parts = []
    for stmt in code.split(' : '):
        m = HEAD.match(stmt)
        if m:
            parts.append(m.group(1))
            continue
        m = re.match(r'^\s*For\s+\w+\s*=\s*(.*?)\s+To\s+(.*?)(?:\s+Step\s+(.*))?$', stmt, re.I)
        if m:
            parts += [g for g in m.groups() if g]
            continue
        m = ASSIGN.match(stmt)
        if m:
            parts.append(m.group(1))
            continue
        # a call statement: its arguments
        m = re.match(r'^\s*[A-Za-z_]\w*\s*\((.*)\)\s*$', stmt)
        if m:
            parts.append('f(' + m.group(1) + ')')
    return parts

def main():
    found = 0
    for path in sys.argv[1:]:
        for n, line in enumerate(open(path, encoding='utf-8', errors='replace'), 1):
            for ex in exprs_of(line):
                try:
                    t = tokens(ex)
                    if not t:
                        continue
                    a, b = parse(t, PB), parse(t, PM)
                except Bad:
                    continue
                if a != b:
                    found += 1
                    print(f'{path}:{n}: {line.strip()}')
    print(f'{found} expression(s) group differently under PureMetal and PureBasic')
    sys.exit(1 if found else 0)

if __name__ == '__main__':
    main()
