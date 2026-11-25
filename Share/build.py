"""Build a self-contained manager. The official Antigravity bundle is never packaged."""
import json, pathlib, plistlib, shutil, subprocess, sys, tempfile
from pathlib import Path
here = Path(__file__).resolve().parent
src = here.parent
out = Path(sys.argv[1]).resolve()
catalog = Path(sys.argv[2]).resolve()
app = out/'Antigravity Skins.app'
resources = app/'Contents/Resources'
helpers = app/'Contents/Helpers'
exe = app/'Contents/MacOS/AntigravitySkins'
for folder in (resources,helpers,exe.parent): folder.mkdir(parents=True,exist_ok=False)
# Only include the public-facing catalog fields and images, never copy application state.
library = resources/'Library';library.mkdir()
themes = []
for record in json.loads((catalog/'catalog.json').read_text()):
    theme = {k:record[k] for k in ('id','name','image','accent')}
    folder = library/theme['id']; folder.mkdir()
    for name in (theme['image'],'preview.jpg'):
        shutil.copyfile(catalog/theme['id']/name,folder/name)
    themes.append(theme)
(library/'catalog.json').write_text(json.dumps(themes,ensure_ascii=False,indent=2))
for f in [here/'skin-template.css',src/'Gallery.icns']:
    shutil.copyfile(f,resources/f.name)
info=dict(CFBundleExecutable=exe.name,CFBundleIdentifier='studio.antigravityskins.share',CFBundleName='Antigravity Skins',CFBundleDisplayName='Antigravity Skins',CFBundlePackageType='APPL',CFBundleVersion='3',CFBundleShortVersionString='1.2',LSMinimumSystemVersion='14.0',CFBundleIconFile='Gallery.icns',NSHighResolutionCapable=True)
(app/'Contents/Info.plist').write_bytes(plistlib.dumps(info))
target=['-target','arm64-apple-macos14']
def run(args): subprocess.run(list(map(str,args)),check=True)
with tempfile.TemporaryDirectory() as temp:
    obj=Path(temp)/'pipe.o'
    run(['clang',*target,'-O2','-c',here/'pipe.c','-o',obj])
    run(['swiftc',*target,'-parse-as-library','-O','-import-objc-header',here/'pipe.h',here/'Shared.swift',here/'Session.swift',obj,'-o',helpers/'ThemeSession'])
    run(['swiftc',*target,'-parse-as-library','-O','-D','SHARE',src/'Gallery.swift',src/'Catalog.swift',src/'SkinEditor.swift',here/'Shared.swift',here/'Launcher.swift','-o',exe])
for f in (helpers/'ThemeSession',app):
    run(['codesign','--force','--options','runtime','--sign','-',f])
run(['codesign','--verify','--deep','--strict',app])
