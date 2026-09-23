import re

filepath = r'd:\FLUTTER_PROJECTS\YallaNews\lib\services\news_blender_service.dart'

with open(filepath, encoding='utf-8') as f:
    content = f.read()

# Find and replace the problematic line 85 using line number approach
lines = content.split('\n')
print(f"Total lines: {len(lines)}")
print(f"Line 84: {repr(lines[83])}")
print(f"Line 85: {repr(lines[84])}")
print(f"Line 86: {repr(lines[85])}")

# Replace the bad regex line (line 85, index 84)
if 'replaceAll(RegExp' in lines[84] and 'masterTitle' in lines[83]:
    lines[84] = "        ? rawTitle!.trim()"
    content = '\n'.join(lines)
    with open(filepath, 'w', encoding='utf-8') as f:
        f.write(content)
    print('Fixed!')
else:
    print('Pattern not matched on expected line')
