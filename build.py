"""Build the local AppKit/SwiftUI gallery from the user's installed Dream Skin artwork."""
import json, pathlib, plistlib, re, shutil, subprocess, sys
from pathlib import Path
src=Path(__file__).resolve().parent
app=Path(sys.argv[1])/'Antigravity Skins.app'
res=app/'Contents/Resources'
exe=app/'Contents/MacOS/AntigravitySkins'
lib=res/'Library'
lib.mkdir(parents=True)
exe.parent.mkdir()
themes=Path.home()/'Library/Application Support/CodexDreamSkinStudio/themes'
catalog=[]
for f in sorted(themes.glob('*/theme.json')):
    data=json.loads(f.read_text())
    ident=f.parent.name
    image=data['image']
    if not re.fullmatch('[a-z0-9-]+',ident) or not re.fullmatch(r'background\.(?:jpg|png|webp)',image):
        continue
    accent=data['colors']['accent']
    assert re.fullmatch('#[a-fA-F0-9]{6}',accent)
    dest=lib/ident
    dest.mkdir()
    shutil.copyfile(f.parent/image,dest/image)
    subprocess.run(['sips','-Z','540','-s','format','jpeg',str(dest/image),'--out',str(dest/'preview.jpg')],stdout=subprocess.DEVNULL,check=True)
    catalog.append(dict(id=ident,name='蜡笔小新' if ident=='crayon-shin-chan' else data['name'],image=image,accent=accent))
(lib/'catalog.json').write_text(json.dumps(catalog,ensure_ascii=False,indent=2))
info=dict(CFBundleExecutable=exe.name,CFBundleIdentifier='local.mason.antigravity-skins',CFBundleName='Antigravity Skins',CFBundleDisplayName='Antigravity Skins',CFBundlePackageType='APPL',CFBundleVersion='3',CFBundleShortVersionString='1.2',LSMinimumSystemVersion='14.0',NSHighResolutionCapable=True)
if (src/'Gallery.icns').exists():
    shutil.copyfile(src/'Gallery.icns',res/'Gallery.icns')
    info['CFBundleIconFile']='Gallery.icns'
(app/'Contents/Info.plist').write_bytes(plistlib.dumps(info))
subprocess.run(['swiftc','-target','arm64-apple-macos14','-O','-parse-as-library',str(src/'Gallery.swift'),str(src/'Catalog.swift'),str(src/'SkinEditor.swift'),'-o',str(exe)],check=True)
subprocess.run(['codesign','--force','--sign','-',str(app)],check=True)
