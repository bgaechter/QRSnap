#!/usr/bin/env python3
"""Generate the one-app/one-test Xcode project with no third-party tooling."""
from pathlib import Path
from hashlib import sha1
import json

ROOT = Path(__file__).resolve().parent.parent
objects = {}
def uid(name): return sha1(name.encode()).hexdigest()[:24].upper()
def quote(value): return json.dumps(str(value))
def obj(key_name, isa, **fields):
    key = uid(key_name)
    objects[key] = '{ isa = ' + isa + '; ' + ' '.join(f'{k} = {v};' for k,v in fields.items()) + ' }'
    return key
def array(items): return '(' + ', '.join(items) + (',' if items else '') + ')'
def settings(values): return '{ ' + ' '.join(f'{k} = {quote(v)};' for k,v in values.items()) + ' }'

app_files = sorted(ROOT.glob('QRSnap/**/*.swift'))
test_files = sorted(ROOT.glob('QRSnapTests/*Tests.swift'))
refs = {}; builds = {}
for path in app_files + test_files:
    rel = str(path.relative_to(ROOT))
    refs[rel] = obj('ref:'+rel, 'PBXFileReference', lastKnownFileType='sourcecode.swift', path=quote(rel), sourceTree='"<group>"')
    builds[rel] = obj('build:'+rel, 'PBXBuildFile', fileRef=refs[rel])
for rel, kind in [('QRSnap/App/Info.plist','text.plist.xml'), ('QRSnap/App/QRSnap.entitlements','text.plist.entitlements'), ('QRSnapTests/Fixtures','folder')]:
    refs[rel] = obj('ref:'+rel,'PBXFileReference',lastKnownFileType=kind,path=quote(rel),sourceTree='"<group>"')
fixtures = obj('build:fixtures','PBXBuildFile',fileRef=refs['QRSnapTests/Fixtures'])
app_product = obj('app_product','PBXFileReference',explicitFileType='wrapper.application',includeInIndex='0',path='QRSnap.app',sourceTree='BUILT_PRODUCTS_DIR')
test_product = obj('test_product','PBXFileReference',explicitFileType='wrapper.cfbundle',includeInIndex='0',path='QRSnapTests.xctest',sourceTree='BUILT_PRODUCTS_DIR')
products = obj('products','PBXGroup',children=array([app_product,test_product]),name='Products',sourceTree='"<group>"')
main = obj('main','PBXGroup',children=array(list(refs.values())+[products]),sourceTree='"<group>"')
def phase(name, kind, files): return obj(name,kind,buildActionMask='2147483647',files=array(files),runOnlyForDeploymentPostprocessing='0')
app_phases = [phase('app_sources','PBXSourcesBuildPhase',[builds[str(p.relative_to(ROOT))] for p in app_files]),phase('app_frameworks','PBXFrameworksBuildPhase',[]),phase('app_resources','PBXResourcesBuildPhase',[])]
test_phases = [phase('test_sources','PBXSourcesBuildPhase',[builds[str(p.relative_to(ROOT))] for p in test_files]),phase('test_frameworks','PBXFrameworksBuildPhase',[]),phase('test_resources','PBXResourcesBuildPhase',[fixtures])]
common = {'SDKROOT':'macosx','MACOSX_DEPLOYMENT_TARGET':'14.0','SWIFT_VERSION':'6.0','CLANG_ENABLE_MODULES':'YES','CODE_SIGN_STYLE':'Manual','CODE_SIGN_IDENTITY':'-'}
def configurations(owner, extra):
    configs=[]
    for name in ['Debug','Release']:
        values={**common, **extra, 'SWIFT_OPTIMIZATION_LEVEL':'-Onone' if name=='Debug' else '-O', 'DEBUG_INFORMATION_FORMAT':'dwarf' if name=='Debug' else 'dwarf-with-dsym'}
        if name=='Debug': values.update(ENABLE_TESTABILITY='YES',SWIFT_ACTIVE_COMPILATION_CONDITIONS='DEBUG')
        configs.append(obj(owner+name,'XCBuildConfiguration',name=name,buildSettings=settings(values)))
    return obj(owner+'configs','XCConfigurationList',buildConfigurations=array(configs),defaultConfigurationIsVisible='0',defaultConfigurationName='Release')
project_configs = configurations('project',{})
app_configs = configurations('app',{'PRODUCT_NAME':'QRSnap','PRODUCT_BUNDLE_IDENTIFIER':'local.benny.QRSnap','INFOPLIST_FILE':'QRSnap/App/Info.plist','CODE_SIGN_ENTITLEMENTS':'QRSnap/App/QRSnap.entitlements','ENABLE_APP_SANDBOX':'YES','ENABLE_HARDENED_RUNTIME':'YES','GENERATE_INFOPLIST_FILE':'NO','LD_RUNPATH_SEARCH_PATHS':'$(inherited) @executable_path/../Frameworks'})
test_configs = configurations('test',{'PRODUCT_NAME':'QRSnapTests','PRODUCT_BUNDLE_IDENTIFIER':'local.benny.QRSnap.tests','GENERATE_INFOPLIST_FILE':'YES','TEST_HOST':'$(BUILT_PRODUCTS_DIR)/QRSnap.app/Contents/MacOS/QRSnap','BUNDLE_LOADER':'$(TEST_HOST)','LD_RUNPATH_SEARCH_PATHS':'$(inherited) @executable_path/../Frameworks @loader_path/../Frameworks'})
app_target=obj('app_target','PBXNativeTarget',name='QRSnap',productName='QRSnap',productReference=app_product,productType='"com.apple.product-type.application"',buildConfigurationList=app_configs,buildPhases=array(app_phases),buildRules='()',dependencies='()')
proxy=obj('proxy','PBXContainerItemProxy',containerPortal=uid('project'),proxyType='1',remoteGlobalIDString=app_target,remoteInfo='QRSnap')
dependency=obj('dependency','PBXTargetDependency',target=app_target,targetProxy=proxy)
test_target=obj('test_target','PBXNativeTarget',name='QRSnapTests',productName='QRSnapTests',productReference=test_product,productType='"com.apple.product-type.bundle.unit-test"',buildConfigurationList=test_configs,buildPhases=array(test_phases),buildRules='()',dependencies=array([dependency]))
project=obj('project','PBXProject',attributes='{ LastUpgradeCheck = 1600; }',buildConfigurationList=project_configs,compatibilityVersion='"Xcode 14.0"',developmentRegion='en',hasScannedForEncodings='0',knownRegions='(en, Base)',mainGroup=main,productRefGroup=products,projectDirPath='""',projectRoot='""',targets=array([app_target,test_target]))
folder=ROOT/'QRSnap.xcodeproj'; folder.mkdir(exist_ok=True)
(folder/'project.pbxproj').write_text('// !$*UTF8*$!\n{\n archiveVersion = 1;\n classes = {};\n objectVersion = 56;\n objects = {\n'+''.join(f'  {key} = {value};\n' for key,value in objects.items())+' };\n rootObject = '+project+';\n}\n')
schemes=folder/'xcshareddata/xcschemes'; schemes.mkdir(parents=True,exist_ok=True)
def reference(target, name): return f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="{name}" BlueprintName="{name.split(".")[0]}" ReferencedContainer="container:QRSnap.xcodeproj"/>'
(schemes/'QRSnap.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries>
<BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{reference(app_target,'QRSnap.app')}</BuildActionEntry>
</BuildActionEntries></BuildAction>
<TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO">{reference(test_target,'QRSnapTests.xctest')}</TestableReference></Testables></TestAction>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{reference(app_target,'QRSnap.app')}</BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{reference(app_target,'QRSnap.app')}</BuildableProductRunnable></ProfileAction>
<AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
''')
print('Generated QRSnap.xcodeproj')
