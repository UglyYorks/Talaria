#!/usr/bin/env python3
"""Summarize Instruments CPU samples only inside measured browser workloads."""
import argparse
from collections import Counter
from datetime import datetime
import json
from pathlib import Path
import xml.etree.ElementTree as ET

parser=argparse.ArgumentParser()
parser.add_argument('--samples',type=Path,required=True)
parser.add_argument('--toc',type=Path,required=True)
parser.add_argument('--frames',type=Path,required=True)
parser.add_argument('--output',type=Path,required=True)
args=parser.parse_args()
origin=datetime.fromisoformat(ET.parse(args.toc).findtext('.//start-date')).timestamp()
cases=json.loads(args.frames.read_text())['cases']
root=ET.parse(args.samples).getroot()
ids={e.get('id'):e for e in root.iter() if e.get('id')}
def resolve(element):
    while element is not None and element.get('ref'):
        element=ids[element.get('ref')]
    return element
groups={}
for row in root.iter('row'):
    sample=resolve(row.find('sample-time'))
    if sample is None:
        continue
    time=origin+int(sample.text)/1e9
    case=next((case for case in cases if case['startUnixSeconds']<=time<=case['endUnixSeconds']),None)
    if case is None:
        continue  # Exclude window/tab creation and warm-up.
    stack=resolve(row.find('tagged-backtrace'))
    if stack is None:
        continue
    backtrace=resolve(stack.find('backtrace'))
    if backtrace is None:
        continue
    frames=[resolve(frame) for frame in backtrace.findall('frame')]
    names=[frame.get('name','') for frame in frames]
    weight=int(resolve(row.find('weight')).text)/1e6
    thread=resolve(row.find('thread')).get('fmt','')
    group=groups.setdefault(case['workload'],{'sampledCPUms':0,'mainCPUms':0,'inclusive':Counter(),'appInclusive':Counter(),'leaf':Counter()})
    group['sampledCPUms']+=weight
    if thread.startswith('Main Thread'):
        group['mainCPUms']+=weight
    for name in set(names):
        group['inclusive'][name]+=weight
        if any(token in name for token in ('-[TL','+[TL','-[Talaria','TLChromeWaveImage','TLColorEdgeData')):
            group['appInclusive'][name]+=weight
    if names:
        group['leaf'][names[0]]+=weight
for group in groups.values():
    for key in ('inclusive','appInclusive','leaf'):
        group[key]=group[key].most_common(60)
args.output.write_text(json.dumps(groups,indent=2)+'\n')
for workload,group in groups.items():
    print(workload,'sampled CPU ms:',group['sampledCPUms'],'main:',group['mainCPUms'])
    for name,weight in group['appInclusive'][:10]:
        print(f'  {weight:.0f} ms {name}')
