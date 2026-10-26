#!/usr/bin/env python3
"""Independent Decimal overlap oracle for a frozen notchGPT history and Swift report.
Usage: python3 scripts/audit-math.py HISTORY MODEL_REPORT OUTPUT
Reads only numeric quota samples; does not read or modify any chat content.
"""
import sys,json,datetime,hashlib,math
from decimal import Decimal,localcontext
from pathlib import Path
from zoneinfo import ZoneInfo
history_path,model_path,output_path=map(Path,sys.argv[1:])
data=history_path.read_bytes();history=json.loads(data);models=json.loads(model_path.read_text())
zone=ZoneInfo('Europe/Rome');epoch=Decimal(978307200);checks=0;days=[];maximum_error=0.0

def d(value): return Decimal(str(value))
def boundary(day,hour):
    return d(datetime.datetime.combine(datetime.date.fromisoformat(day),datetime.time(hour),zone).timestamp())-epoch

def compare(actual,expected,label,tolerance=1e-5):
    global checks,maximum_error
    difference=abs(float(actual)-float(expected));maximum_error=max(maximum_error,difference);checks+=1
    assert difference<tolerance,(label,actual,str(expected),difference)

for model in models:
    day=model['day'];total=Decimal(0);coverage=Decimal(0);estimated_coverage=Decimal(0);sample_count=0
    bins=[{'amount':None,'coverage':Decimal(0)} for _ in range(16)]
    for group,hour in enumerate([9,14]):
        candidates=[b for b in history['blocks'] if b['day']==day and b['startHour']==hour]
        if not candidates:continue
        block=candidates[-1];samples=block['samples'];opening=boundary(day,hour);closing=boundary(day,hour+4)
        assert samples and opening<=d(samples[0]['time'])<=closing
        assert datetime.date.fromisoformat(day).weekday()<5
        previous_time=d(samples[0]['time']);previous_used=Decimal(0)
        for index,sample in enumerate(samples):
            t=d(sample['time']);used=d(sample['used']);start=d(sample.get('intervalStart',previous_time))
            assert used.is_finite() and used>=previous_used and t<=closing
            assert (index==0 or t>previous_time) and previous_time<=start<=t
            previous_time=t;previous_used=used
        sample_count+=len(samples);total+=d(samples[-1]['used'])
        if d(samples[0]['used'])>0:
            assert d(samples[0]['time'])==opening
            bins[group*8]['amount']=d(samples[0]['used'])
        for previous,sample in zip(samples,samples[1:]):
            start=d(sample.get('intervalStart',previous['time']));end=d(sample['time']);delta=d(sample['used'])-d(previous['used']);duration=end-start
            if duration==0:
                slot=int((end-opening)//1800)
                if delta>0 and 0<=slot<8:
                    b=bins[group*8+slot];b['amount']=(b['amount'] or Decimal(0))+delta
                continue
            for slot in range(8):
                left=opening+slot*1800;right=left+1800
                overlap=max(Decimal(0),min(right,end)-max(left,start))
                if not overlap:continue
                b=bins[group*8+slot];b['amount']=(b['amount'] or Decimal(0))+delta*overlap/duration;b['coverage']+=overlap
            coverage+=duration
            if duration>180:estimated_coverage+=duration
    compare(model['total'],total,day+' total')
    compare(model['trackedSeconds'],coverage,day+' coverage')
    compare(sum((b['amount'] or Decimal(0)) for b in bins),total,day+' conservation')
    for index,(actual,expected) in enumerate(zip(model['bars'],bins)):
        assert (actual['amount'] is None)==(expected['amount'] is None),(day,index,'missing/zero distinction')
        if expected['amount'] is not None:compare(actual['amount'],expected['amount'],f'{day} bin {index}')
        compare(actual['coverage'],expected['coverage'],f'{day} coverage {index}')
    compare(model['dailyUsedPercent'],total/20*100,day+' daily denominator')
    days.append({'day':day,'samples':sample_count,'observedWeeklyPoints':float(total),'dailyTargetUsedPercent':float(total/20*100),'coveredHours':float(coverage/3600),'longIntervalEstimatedHours':float(estimated_coverage/3600)})
last=datetime.date.fromisoformat(max(row['day'] for row in days));first=last-datetime.timedelta(days=6)
week=[row for row in days if row['day']>=str(first)]
report={'sourceSHA256':hashlib.sha256(data).hexdigest(),'source':str(history_path.resolve()),'timeZone':'Europe/Rome','periodStart':str(first),'periodEnd':str(last),'checks':checks,'maximumAbsoluteError':maximum_error,'samples':sum(row['samples'] for row in days),'weekObservedPoints':sum(row['observedWeeklyPoints'] for row in week),'week':week,'allRetainedDays':days,'limits':['Stored cumulative history is not a complete log of the raw quota polls. Historical effects of reset jitter cannot be reconstructed exactly.','Legacy samples without intervalStart cannot establish that every interval was observed. Long intervals retain estimated timing.','Weekly percentage-point increments across reset cycles are not the remaining percentage of a single weekly cycle.']}
output_path.write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report,indent=2))
