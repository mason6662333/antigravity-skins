"""Install the gallery bridge into a staged copy of a local Antigravity desktop client."""
from pathlib import Path
import hashlib, json, plistlib, re, shutil, struct, sys
app=Path(sys.argv[1])/'Contents'
res=app/'Resources'
asar=res/'app.asar'
raw=asar.read_bytes()
sha=lambda data: hashlib.sha256(data).hexdigest()
header=json.loads(raw[16:16+struct.unpack_from('<I',raw,12)[0]])
start=8+struct.unpack_from('<I',raw,4)[0]
def entries(node):
    for v in node['files'].values():
        if 'files' in v: yield from entries(v)
        elif 'offset' in v: yield v
HOOK="    require(require('path').join(process.resourcesPath, 'ag-skins-bridge.cjs')).attach(hubContents, url);\n"
def patch_utils(s):
    if 'ag-skins-bridge.cjs' in s:
        return s
    legacy=re.compile(r"    // Apply the local wallpaper only.*?(?=    win\.on\('focus')",re.S)
    if legacy.search(s):
        return legacy.sub(HOOK+"\n",s,count=1)
    anchor=re.compile(r"(    registerWindowWebContents\(win, hubContents\);\r?\n)(    win\.on\('focus', notifyHubFocusChange\);)")
    matches=list(anchor.finditer(s))
    assert len(matches)==1,f"Expected unique Hub hook anchor in dist/utils.js, found {len(matches)}"
    return anchor.sub(r"\1"+HOOK+r"\2",s,count=1)
data=bytearray()
edits={'dist/utils.js':patch_utils}
info=plistlib.loads((app/'Info.plist').read_bytes())
if len(sys.argv)>2: # Isolated GUI acceptance against an existing Hub.
    url=sys.argv[2]
    assert re.fullmatch(r'https://127\.0\.0\.1:\d+/?',url)
    def main(s):
        for old,new in [('const DEV_URL = process.env.DEV_URL;',f'const DEV_URL = {json.dumps(url)};'),('await (0, ideInstall_1.maybeShowIdeInstallWizard)(storageManager);','/* Separate gallery acceptance window. */'),('if (DEV_URL) {',"if (DEV_URL) { (0, languageServer_1.setupLocalCertTrust)();")]:
            assert s.count(old)==1
            s=s.replace(old,new)
        return s
    def package(s):
        d=json.loads(s);d.update(name='antigravity-gallery-preview',productName='Antigravity Gallery Preview');return json.dumps(d)
    edits.update({'dist/main.js':main,'package.json':package})
    info.update(CFBundleIdentifier='local.mason.antigravity-gallery-preview',CFBundleDisplayName='Antigravity Gallery Preview')
transforms={}
for path,fn in edits.items():
    e=header
    for part in path.split('/'): e=e['files'][part]
    transforms[id(e)]=fn
changed=False
for e in sorted(entries(header),key=lambda e:int(e['offset'])):
    offset=int(e['offset'])
    segment=raw[start+offset:start+offset+e['size']]
    if id(e) in transforms:
        new=transforms[id(e)](segment.decode()).encode()
        if new!=segment:
            changed=True
            segment=new
            e['size']=len(segment)
            if 'integrity' in e:
                it=e['integrity'];bs=it['blockSize'];it.update(hash=sha(segment),blocks=[sha(segment[k:k+bs]) for k in range(0,len(segment),bs)])
    e['offset']=str(len(data));data.extend(segment)
if changed:
    header_bytes=json.dumps(header,ensure_ascii=False,separators=(',',':')).encode()
    blob=struct.pack('<I',len(header_bytes))+header_bytes
    blob+=bytes(-len(blob)%4)
    asar.write_bytes(struct.pack('<III',4,len(blob)+4,len(blob))+blob+data)
    if 'ElectronAsarIntegrity' in info and 'Resources/app.asar' in info['ElectronAsarIntegrity']:
        info['ElectronAsarIntegrity']['Resources/app.asar']['hash']=sha(header_bytes)
    (app/'Info.plist').write_bytes(plistlib.dumps(info))
shutil.copyfile(Path(__file__).with_name('bridge.cjs'),res/'ag-skins-bridge.cjs')
