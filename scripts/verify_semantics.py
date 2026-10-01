import glob, re, sys

# Check selector definitions and method declarations
with open('Source/MapPickerViewController+Private.h', 'r', encoding='utf-8') as f:
    private_h = f.read()

with open('Source/MapPickerViewController.h', 'r', encoding='utf-8') as f:
    public_h = f.read()

with open('Source/MapPickerViewController.m', 'r', encoding='utf-8') as f:
    main_m = f.read()

with open('Source/MapPickerViewController+Route.m', 'r', encoding='utf-8') as f:
    route_m = f.read()

with open('Source/MapPickerViewController+Bookmarks.m', 'r', encoding='utf-8') as f:
    bookmarks_m = f.read()

all_code = private_h + '\n' + public_h + '\n' + main_m + '\n' + route_m + '\n' + bookmarks_m

# Find all @selector(...)
selectors = set(re.findall(r'@selector\(([a-zA-Z0-9_:]+)\)', all_code))
print(f"Found {len(selectors)} unique selectors across MapPickerViewController files:")

missing = []
for sel in selectors:
    # check if method definition exists
    # e.g. "handleApply" -> "- (void)handleApply" or "handleApply:"
    parts = sel.split(':')
    base = parts[0]
    pattern = rf'[-+]\s*\([^)]+\)\s*{base}'
    if not re.search(pattern, all_code):
        missing.append(sel)

if missing:
    print("WARNING: Missing selectors:")
    for m in missing:
        print("  -", m)
    sys.exit(1)
else:
    print("SUCCESS: All @selector references have corresponding method definitions!")

# Check property accesses
prop_decls = set(re.findall(r'@property\s*\([^)]*\)\s*[^;]+?\b([a-zA-Z0-9_]+);', private_h + '\n' + public_h))
print(f"Found {len(prop_decls)} declared properties in private/public headers.")

# Check for undefined self.xxx
self_accesses = set(re.findall(r'\bself\.([a-zA-Z0-9_]+)\b', main_m + '\n' + route_m + '\n' + bookmarks_m))
# Exclude known UIViewController properties
uivc_props = {
    'view', 'tableView', 'isEditing', 'navigationController', 'navigationItem', 'tabBarController',
    'presentedViewController', 'presentingViewController', 'modalPresentationStyle',
    'sheetPresentationController', 'preferredContentSize', 'title'
}
unknown_props = []
for prop in self_accesses:
    if prop not in prop_decls and prop not in uivc_props:
        unknown_props.append(prop)

if unknown_props:
    print("WARNING: Unknown properties on self:")
    for p in unknown_props:
        print("  -", p)
    sys.exit(1)
else:
    print("SUCCESS: All self.property accesses match declared properties or UIViewController base properties!")
