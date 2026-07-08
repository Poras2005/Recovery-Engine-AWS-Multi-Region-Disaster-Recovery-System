#!/usr/bin/env python3
"""
Simulates a Mumbai regional failure by stopping all primary EC2
instances, then monitors Route 53 switching to Singapore.
"""

import boto3, getpass, os, requests, socket, time, yaml
from datetime import datetime
from pathlib import Path

cfg = yaml.safe_load(open(Path(__file__).parent.parent / 'config.yaml'))
MUMBAI = cfg['aws']['primary_region']
DOMAIN = cfg['route53']['domain']
HPATH  = cfg['route53']['health_check_path']

print('\n Failover Test — enter AWS credentials')
KEY_ID = os.environ.get('AWS_ACCESS_KEY_ID') or getpass.getpass(' AWS Access Key ID     : ')
SECRET = os.environ.get('AWS_SECRET_ACCESS_KEY') or getpass.getpass(' AWS Secret Access Key : ')

def ec2(): return boto3.client('ec2', region_name=MUMBAI,
                               aws_access_key_id=KEY_ID, aws_secret_access_key=SECRET)

def get_running_ids():
    r = ec2().describe_instances(Filters=[
        {'Name':'tag:Env','Values':['production']},
        {'Name':'instance-state-name','Values':['running']}])
    return [i['InstanceId'] for res in r['Reservations']
            for i in res['Instances']]

def check_health():
    try:
        r = requests.get(f'http://{DOMAIN}{HPATH}', timeout=5)
        return r.status_code, r.json()
    except Exception as e:
        return None, str(e)

def dns_ip():
    try: return socket.gethostbyname(DOMAIN)
    except: return 'unresolved'

print(f'\n[Baseline] DNS={dns_ip()}')
status, body = check_health()
print(f'[Baseline] HTTP={status} | {body}')

ids = get_running_ids()
print(f'\nStopping {len(ids)} Mumbai instance(s): {ids}')
if ids:
    ec2().stop_instances(InstanceIds=ids)

print('\nMonitoring failover for 120 seconds...\n')
for i in range(1, 13):
    time.sleep(10)
    ip = dns_ip()
    status, body = check_health()
    ts = datetime.utcnow().strftime('%H:%M:%S')
    print(f'[{ts}] {i*10:>3}s  DNS={ip:<16}  HTTP={status}  {body}')

print('\nTest complete. Run python3 deploy.py --spinup to restore.')
