"""Generate a minimal local Xcode project without downloading XcodeGen."""
from pathlib import Path
import hashlib,json,sys

root=Path(__file__).resolve().parents[1]
source=root/'app/ios/ChampionsOnDevice'
project=root/'app/ios/ChampionsOnDeviceResearch.xcodeproj'
project.mkdir(exist_ok=True)
def uid(label):return hashlib.sha256(label.encode()).hexdigest()[:24].upper()
def q(text):return json.dumps(str(text),ensure_ascii=False)
objects=[]
def obj(key,body):objects.append(f'{uid(key)} = {{ {body} }};')
files=sorted(source.glob('*.swift'))
resources=sorted(source.glob('*.xcprivacy'))
for p in files:
 obj('ref:'+p.name,f'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {q(p.name)}; sourceTree = "<group>";')
 obj('build:'+p.name,f'isa = PBXBuildFile; fileRef = {uid("ref:"+p.name)};')
obj('product','isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = ChampionsOnDeviceResearch.app; sourceTree = BUILT_PRODUCTS_DIR;')
for p in resources:
 obj('ref:'+p.name,f'isa = PBXFileReference; lastKnownFileType = text.xml; path = {q(p.name)}; sourceTree = "<group>";')
 obj('build:'+p.name,f'isa = PBXBuildFile; fileRef = {uid("ref:"+p.name)};')
obj('sources-group','isa = PBXGroup; path = ChampionsOnDevice; sourceTree = "<group>"; children = ('+','.join(uid('ref:'+p.name) for p in files+resources)+');')
obj('products-group',f'isa = PBXGroup; name = Products; sourceTree = "<group>"; children = ({uid("product")});')
obj('root-group',f'isa = PBXGroup; sourceTree = "<group>"; children = ({uid("sources-group")},{uid("products-group")});')
obj('source-phase','isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; runOnlyForDeploymentPostprocessing = 0; files = ('+','.join(uid('build:'+p.name) for p in files)+');')
obj('framework-phase','isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; runOnlyForDeploymentPostprocessing = 0; files = ();')
obj('resource-phase','isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; runOnlyForDeploymentPostprocessing = 0; files = ('+','.join(uid('build:'+p.name) for p in resources)+');')
for config in ('Debug','Release'):
 common='SDKROOT = iphoneos; IPHONEOS_DEPLOYMENT_TARGET = 27.0; SWIFT_VERSION = 5.0; CLANG_ENABLE_MODULES = YES;'
 obj('project:'+config,f'isa = XCBuildConfiguration; name = {config}; buildSettings = {{ {common} }};')
 target=common+' TARGETED_DEVICE_FAMILY = 1; PRODUCT_NAME = ChampionsOnDeviceResearch; PRODUCT_BUNDLE_IDENTIFIER = com.zeek10191019.championsresearch; CODE_SIGNING_ALLOWED = NO; GENERATE_INFOPLIST_FILE = NO; INFOPLIST_FILE = ChampionsOnDevice/Info.plist; SWIFT_OPTIMIZATION_LEVEL = "-Onone"; ENABLE_USER_SCRIPT_SANDBOXING = YES;'
 obj('target:'+config,f'isa = XCBuildConfiguration; name = {config}; buildSettings = {{ {target} }};')
for owner in ('project','target'):
 obj(owner+'-configs',f'isa = XCConfigurationList; buildConfigurations = ({uid(owner+":Debug")},{uid(owner+":Release")}); defaultConfigurationIsVisible = 0; defaultConfigurationName = Debug;')
obj('target',f'isa = PBXNativeTarget; name = ChampionsOnDeviceResearch; productName = ChampionsOnDeviceResearch; productType = "com.apple.product-type.application"; productReference = {uid("product")}; buildConfigurationList = {uid("target-configs")}; buildPhases = ({uid("source-phase")},{uid("framework-phase")},{uid("resource-phase")}); buildRules = (); dependencies = ();')
obj('project',f'isa = PBXProject; attributes = {{ LastUpgradeCheck = 2700; }}; buildConfigurationList = {uid("project-configs")}; compatibilityVersion = "Xcode 14.0"; developmentRegion = en; hasScannedForEncodings = 0; knownRegions = (en,Base); mainGroup = {uid("root-group")}; productRefGroup = {uid("products-group")}; projectDirPath = ""; projectRoot = ""; targets = ({uid("target")});')
text='// !$*UTF8*$!\n{ archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n'+'\n'.join(objects)+'\n}; rootObject = '+uid('project')+'; }\n'
(project/'project.pbxproj').write_text(text)
print('XCODE_PROJECT_GENERATED',len(files),'Swift files')
