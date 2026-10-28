import subprocess, sys, time, torch

D = '/sys/bus/pci/devices/0000:01:00.0/power/runtime_status'
label = sys.argv[1] if len(sys.argv) > 1 else ''
runs = int(sys.argv[2]) if len(sys.argv) > 2 else 3


def state():
    rs = open(D).read().strip()
    rec = subprocess.run(['systemctl', 'is-active', 'nvidia-vbios-reconcile.service'],
                         capture_output=True, text=True).stdout.strip()
    return f'gpu={rs} reconcile={rec}'


print(f'[{time.strftime("%H:%M:%S")}] {label} before: {state()}')
for run in range(1, runs + 1):
    r = {}
    for name, dt in [('FP16', torch.float16), ('BF16', torch.bfloat16), ('FP32', torch.float32)]:
        a = torch.randn(4096, 4096, device='cuda', dtype=dt)
        b = torch.randn(4096, 4096, device='cuda', dtype=dt)
        for _ in range(20):
            torch.mm(a, b)
        torch.cuda.synchronize()
        t0 = time.perf_counter()
        for _ in range(100):
            torch.mm(a, b)
        torch.cuda.synchronize()
        r[name] = round(2 * 4096**3 * 100 / (time.perf_counter() - t0) / 1e12, 2)
        del a, b
        torch.cuda.empty_cache()
    clk = subprocess.run(['nvidia-smi', '--query-gpu=clocks.gr,power.draw,temperature.gpu',
                          '--format=csv,noheader'], capture_output=True, text=True).stdout.strip()
    print(f'[{time.strftime("%H:%M:%S")}] run {run}: {r} | {clk} | {state()}')
