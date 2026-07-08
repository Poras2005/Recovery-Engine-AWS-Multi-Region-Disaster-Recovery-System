#!/usr/bin/env python3
"""Restore both regions to full DR capacity."""

import boto3, getpass, os, time, yaml
from pathlib import Path

cfg = yaml.safe_load(open(Path(__file__).parent.parent / 'config.yaml'))
des = cfg['autoscaling']['desired_instances']
mn  = cfg['autoscaling']['min_instances']
mx  = cfg['autoscaling']['max_instances']

print('\n Spinup — enter AWS credentials')
KEY_ID = os.environ.get('AWS_ACCESS_KEY_ID') or getpass.getpass(' AWS Access Key ID     : ')
SECRET = os.environ.get('AWS_SECRET_ACCESS_KEY') or getpass.getpass(' AWS Secret Access Key : ')

CONFIGS = [
    {'region': cfg['aws']['primary_region'],   'asg': 'dr-asg-mumbai'},
    {'region': cfg['aws']['secondary_region'], 'asg': 'dr-asg-singapore'},
]

for c in CONFIGS:
    asc = boto3.client('autoscaling', region_name=c['region'],
                       aws_access_key_id=KEY_ID, aws_secret_access_key=SECRET)
    asc.update_auto_scaling_group(
        AutoScalingGroupName=c['asg'],
        MinSize=mn, MaxSize=mx, DesiredCapacity=des)
    print(f' {c["asg"]:30s} -> desired={des}')
    
    print(f'  Waiting for instances to be InService...', end='', flush=True)
    for _ in range(18): # up to 3 minutes
        time.sleep(10)
        r = asc.describe_auto_scaling_groups(AutoScalingGroupNames=[c['asg']])
        healthy = [i for i in r['AutoScalingGroups'][0]['Instances']
                   if i['LifecycleState'] == 'InService']
        print('.', end='', flush=True)
        if len(healthy) >= des:
            print(f' Ready ({len(healthy)} InService)')
            break
    else:
        print(' Timed out — check AWS console')

print('\nSpinup done. Full DR capacity restored.')
print('Run python3 deploy.py --failover-test to simulate failure.')
