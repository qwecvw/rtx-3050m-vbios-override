#!/bin/bash
# Sustained load: gpu-burn FP32, gpu-burn tensor (TF32), PyTorch FP16 GEMM.
# Logs power/clock/temp/throttle every second; aborts a stage above TEMP_LIMIT.
DUR=${DUR:-300}
TEMP_LIMIT=${TEMP_LIMIT:-92}
BURN_DIR=${BURN_DIR:?set BURN_DIR to a gpu-burn checkout containing compare.fatbin}
OUT=${OUT:-$PWD/stress_$(date +%Y%m%d_%H%M)}
mkdir -p "$OUT"
echo "AC online: $(cat /sys/class/power_supply/A*/online 2>/dev/null | head -1)" | tee "$OUT/info.txt"
nvidia-smi --query-gpu=power.max_limit,power.default_limit --format=csv | tee -a "$OUT/info.txt"

monitor() {
    nvidia-smi --query-gpu=timestamp,power.draw,clocks.gr,clocks.mem,temperature.gpu,utilization.gpu,clocks_event_reasons.active \
        --format=csv,noheader,nounits -l 1 > "$OUT/$1.csv" &
    MON=$!
}

guard() {
    while kill -0 "$1" 2>/dev/null; do
        t=$(nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader,nounits)
        if [ "$t" -ge "$TEMP_LIMIT" ]; then echo "TEMP $t >= $TEMP_LIMIT, stopping" | tee -a "$OUT/info.txt"; kill "$1"; fi
        sleep 2
    done
}

summary() {
    python3 - "$OUT/$1.csv" "$1" <<'EOF'
import sys, csv
rows = [r for r in csv.reader(open(sys.argv[1])) if len(r) >= 7]
def col(i):
    out = []
    for r in rows[5:]:
        try: out.append(float(r[i]))
        except ValueError: pass
    return out
p, c, t = col(1), col(2), col(4)
BITS = {0x1: 'idle', 0x2: 'app-clocks', 0x4: 'power-cap', 0x8: 'hw-slowdown', 0x10: 'sync-boost',
        0x20: 'sw-thermal', 0x40: 'hw-thermal', 0x80: 'hw-power-brake', 0x100: 'display-clock'}
reasons = {}
for r in rows[5:]:
    try: mask = int(r[6].strip(), 16)
    except ValueError: continue
    name = '+'.join(v for k, v in BITS.items() if mask & k) or 'none'
    reasons[name] = reasons.get(name, 0) + 1
if p:
    print(f'{sys.argv[2]}: power avg {sum(p)/len(p):.1f} max {max(p):.1f} W | clock avg {sum(c)/len(c):.0f} min {min(c):.0f} MHz | temp max {max(t):.0f} C | throttle {reasons}')
EOF
}

run_stage() {
    name=$1; shift
    echo "=== $name ($DUR s)"
    monitor "$name"
    "$@" > "$OUT/$name.log" 2>&1 &
    PID=$!
    guard $PID
    wait $PID
    kill $MON 2>/dev/null
    summary "$name" | tee -a "$OUT/summary.txt"
    tail -3 "$OUT/$name.log"
    sleep 30
}

cd "$BURN_DIR"
run_stage burn_fp32 ${GPU_BURN:-gpu-burn} "$DUR"
run_stage burn_tc ${GPU_BURN:-gpu-burn} -tc "$DUR"
run_stage torch_fp16 python3 -c "
import time, torch
a = torch.randn(4096, 4096, device='cuda', dtype=torch.float16); b = torch.randn_like(a)
end = time.time() + $DUR; n = 0; t0 = time.time(); w = t0
while time.time() < end:
    for _ in range(50): torch.mm(a, b)
    torch.cuda.synchronize(); n += 50
    if time.time() - w >= 30:
        print(f'{time.time()-t0:5.0f}s  FP16 {2*4096**3*n/(time.time()-w)/1e12:.2f} TFLOPS', flush=True); n = 0; w = time.time()
"
echo "Logs: $OUT"
