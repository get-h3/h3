import json
import urllib.request

# PUT to set cooldown
data = json.dumps({"CooldownS": 43200}).encode()
req = urllib.request.Request('http://127.0.0.1:9090/api/v1/projects/h3', data=data, method='PUT', headers={'Content-Type': 'application/json'})
try:
    with urllib.request.urlopen(req, timeout=5) as resp:
        result = json.loads(resp.read())
    print(f"PUT result: {json.dumps(result, default=str)}")
except Exception as e:
    print(f"PUT ERROR: {e}")

# GET to verify
req2 = urllib.request.Request('http://127.0.0.1:9090/api/v1/projects/h3')
try:
    with urllib.request.urlopen(req2, timeout=5) as resp:
        data = json.loads(resp.read())
    p = data.get('project', data)
    print(f"VERIFIED: Enabled={p.get('Enabled')}, CooldownS={p.get('CooldownS')}")
except Exception as e:
    print(f"GET ERROR: {e}")
