import glob, os, sys

files = glob.glob('Source/*.[hm]')
errors = []

for f in files:
    with open(f, 'r', encoding='utf-8', errors='ignore') as fp:
        content = fp.read()
    
    stack = []
    pairs = {')': '(', ']': '[', '}': '{'}
    in_str = False
    str_char = ''
    in_line_comment = False
    in_block_comment = False
    i = 0
    line_no = 1
    col_no = 1
    
    while i < len(content):
        c = content[i]
        if c == '\n':
            line_no += 1
            col_no = 0
            in_line_comment = False
        
        if in_line_comment:
            pass
        elif in_block_comment:
            if content[i:i+2] == '*/':
                in_block_comment = False
                i += 1
        elif in_str:
            if c == '\\':
                i += 1
            elif c == str_char:
                in_str = False
        else:
            if content[i:i+2] == '//':
                in_line_comment = True
                i += 1
            elif content[i:i+2] == '/*':
                in_block_comment = True
                i += 1
            elif c in ('"', "'"):
                in_str = True
                str_char = c
            elif c in ('(', '[', '{'):
                stack.append((c, line_no, col_no))
            elif c in (')', ']', '}'):
                if not stack:
                    errors.append(f'{f}:{line_no}:{col_no}: Unmatched closing {c}')
                else:
                    top, t_line, t_col = stack.pop()
                    if pairs[c] != top:
                        errors.append(f'{f}:{line_no}:{col_no}: Mismatched {c} for {top} at line {t_line}')
        i += 1
        col_no += 1
        
    if stack:
        for top, t_line, t_col in stack:
            errors.append(f'{f}:{t_line}:{t_col}: Unclosed {top}')

if errors:
    print('\n'.join(errors))
    sys.exit(1)
else:
    print(f'SUCCESS: Verified all {len(files)} files. 0 syntax/bracket pairing errors!')
