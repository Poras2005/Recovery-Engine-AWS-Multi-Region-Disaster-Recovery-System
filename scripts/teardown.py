#!/usr/bin/env python3
"""Scale both regions down to save money. Run every night."""

import boto3, getpass, os, yaml
from pathlib import Path

cfg = yaml.safe_load(open(Path(__file__).parent.parent / 'config.yaml'))
print('\n Teardown — enter AWS credentials')
KEY_ID = os.environ.get('AWS_ACCESS_KEY_ID') or getpass.getpass(' AWS Access Key ID     : ')
SECRET = os.environ.get('AWS_SECRET_ACCESS_KEY') or getpass.getpass(' AWS Secret Access Key : ')

CONFIGS = [
    {'region': cfg['aws']['primary_region'],   'asg': 'dr-asg-mumbai',    'min':1,'max':1,'des':1},
    {'region': cfg['aws']['secondary_region'], 'asg': 'dr-asg-singapore', 'min':0,'max':0,'des':0},
]

for c in CONFIGS:
    asc = boto3.client('autoscaling', region_name=c['region'],
                       aws_access_key_id=KEY_ID, aws_secret_access_key=SECRET)
    asc.update_auto_scaling_group(
        AutoScalingGroupName=c['asg'],
        MinSize=c['min'], MaxSize=c['max'], DesiredCapacity=c['des'])
    print(f' {c["asg"]:30s} -> desired={c["des"]}')

print('\nTeardown done. Mumbai: 1 instance | Singapore: 0 instances')
print('Run python3 deploy.py --spinup to restore.')
