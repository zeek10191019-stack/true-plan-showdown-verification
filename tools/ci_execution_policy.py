"""Explicit host/build roles. An iPhoneOS cross-build never proves iOS runtime OCR."""
ROLE_RUNNERS={'IOS27_NATIVE':('xcode-27','arm64'),'PORTABLE_OCR':('macos-26-intel','x86_64'),
    'MACOS26_BUILD_AND_OCR':('macos-26-intel','x86_64')}

def execution_policy(role,system,machine,iphoneos_sdk,host_version=None):
    if role not in ROLE_RUNNERS:raise ValueError('UNKNOWN_CI_ROLE')
    runner,expected=ROLE_RUNNERS[role]
    if system!='Darwin' or machine!=expected:raise ValueError('CI_ROLE_PLATFORM_MISMATCH')
    try:major=int(iphoneos_sdk.split('.')[0])
    except (ValueError,TypeError,AttributeError):raise ValueError('CI_SDK_VERSION')
    requires_build=role in ('IOS27_NATIVE','MACOS26_BUILD_AND_OCR')
    if major<(27 if requires_build else 17):raise ValueError('CI_ROLE_SDK_TOO_OLD')
    if role=='MACOS26_BUILD_AND_OCR' and (not isinstance(host_version,str) or host_version.split('.')[0]!='26'):
        raise ValueError('CI_ROLE_HOST_OS_MISMATCH')
    return {'role':role,'runner_label':runner,'machine':machine,'requires_iPhoneOS27_build':requires_build,
        'iPhoneOS_build_scope':'REQUIRED_CURRENT_SOURCE' if requires_build else 'NOT_RUN_PORTABLE_ROLE'}
