"""Copy social preview assets beside an existing Godot Web export."""
from pathlib import Path
import shutil
import sys

project = Path(__file__).resolve().parents[1]
destination = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else project / 'build/web'
html = destination / 'index.html'
if not html.is_file():
    raise SystemExit('Export the Web preset before packaging: ' + str(html))
if 'branding/og-image-v1.png' not in html.read_text(encoding='utf-8'):
    raise SystemExit('The exported page is missing the current social metadata. Re-export Web.')
branding = destination / 'branding'
branding.mkdir(exist_ok=True)
for name in ['og-image-v1.png', 'app-icon-v1.png']:
    shutil.copy2(project / 'web/branding' / name, branding / name)
if 'id="loading-title"' in html.read_text(encoding='utf-8'):
    fonts = project / 'assets/fonts/tsap-tsarap'
    for name in ['Tsap-Tsarap.ttf', 'readme_216.txt']:
        shutil.copy2(fonts / name, branding / name)
print('Packaged Web branding: ' + str(branding))
