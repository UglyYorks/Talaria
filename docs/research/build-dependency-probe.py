#!/usr/bin/env python3
"""Validate incremental build dependencies after an initial desktop build.

Touches selected inputs temporarily, restores their timestamps, and restores
the default compiler flags and signed app bundle. Requires normal build access.
"""
from pathlib import Path
import json
import os
import subprocess
import time
root=Path(__file__).resolve().parents[2]
results=[]
def snapshot():
    return {str(p.relative_to(root)):p.stat().st_mtime_ns for p in (root/'build/app-objects').rglob('*.o')}
def run(label,target='build/bin/Talaria',extra=()):
    before=snapshot(); exe=root/'build/bin/Talaria'; stamp=exe.stat().st_mtime_ns if exe.exists() else 0
    start=time.monotonic()
    with open(f'/private/tmp/talaria-build-{label}.log','w') as log:
        subprocess.run(['make','-j8',target,*extra],cwd=root,stdout=log,stderr=subprocess.STDOUT,check=True)
    after=snapshot(); changed=sorted(k for k in after if before.get(k)!=after[k]); relinked=exe.exists() and exe.stat().st_mtime_ns!=stamp
    result={'case':label,'seconds':round(time.monotonic()-start,3),'rebuilt_objects':changed,'relinked_app':relinked};results.append(result)
    print(label,len(changed),'objects; relinked:',relinked,flush=True)
    return result
run('prepare')
assert not run('noop')['rebuilt_objects']
for label,path in [('leaf-header','Source/TLAgentProtocol.h'),('shared-header','Source/Theme.h'),('resource','Source/MarkdownCode.js')]:
    file=root/path; old=file.stat()
    try:
        time.sleep(1.1) # macOS bundled make compares dependency timestamps at second resolution.
        os.utime(file,None)
        result=run(label,'build' if label=='resource' else 'build/bin/Talaria')
        if label=='leaf-header': assert 0<len(result['rebuilt_objects'])<10 and result['relinked_app']
        if label=='shared-header': assert len(result['rebuilt_objects'])>10
        if label=='resource': assert not result['rebuilt_objects'] and not result['relinked_app']
    finally: os.utime(file,ns=(old.st_atime_ns,old.st_mtime_ns))
result=run('compiler-flags','build/app-objects/TLAgentProtocol.m.o',('OBJCFLAGS=-fobjc-arc -fmodules -Wall -mmacosx-version-min=13.0 -DTL_BUILD_DEPENDENCY_PROBE=1',))
assert 'build/app-objects/TLAgentProtocol.m.o' in result['rebuilt_objects']
run('restore-defaults','build')
assert not run('final-noop','build')['rebuilt_objects']
(root/'docs/research/build-validation.json').write_text(json.dumps(results,indent=2)+'\n')
