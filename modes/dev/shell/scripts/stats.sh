#!/usr/bin/env bash
# Prints one JSON line per second: cpu %, ram, gpu %, vram, cpu temp, network rates.
# GPU: NVIDIA via nvidia-smi, AMD via sysfs. Missing values are reported as -1.

prev_total=0; prev_idle=0; prev_rx=0; prev_tx=0; tick=0
gpu=-1; vram_used=-1; vram_total=-1

cpu_temp() {
    for h in /sys/class/hwmon/hwmon*; do
        n=$(cat "$h/name" 2>/dev/null)
        case "$n" in k10temp|coretemp|zenpower)
            t=$(cat "$h/temp1_input" 2>/dev/null) && { echo $((t / 1000)); return; } ;;
        esac
    done
    echo -1
}

read_gpu() {
    # the AMD card first (the main 24 GB card here); nvidia-smi only if there's none
    for d in /sys/class/drm/card*/device; do
        if [[ -r "$d/gpu_busy_percent" && -r "$d/mem_info_vram_total" ]]; then
            gpu=$(cat "$d/gpu_busy_percent"); vram_used=$(cat "$d/mem_info_vram_used"); vram_total=$(cat "$d/mem_info_vram_total")
            return
        fi
    done
    if command -v nvidia-smi >/dev/null 2>&1; then
        IFS=', ' read -r gpu vram_used vram_total < <(nvidia-smi --query-gpu=utilization.gpu,memory.used,memory.total --format=csv,noheader,nounits 2>/dev/null | head -n1)
        # MiB -> bytes
        [[ -n "$vram_used" ]] && vram_used=$((vram_used * 1048576)) && vram_total=$((vram_total * 1048576))
        return
    fi
    for d in /sys/class/drm/card*/device; do
        if [[ -r "$d/gpu_busy_percent" && -r "$d/mem_info_vram_total" ]]; then
            gpu=$(cat "$d/gpu_busy_percent"); vram_used=$(cat "$d/mem_info_vram_used"); vram_total=$(cat "$d/mem_info_vram_total")
            return
        fi
    done
}

while :; do
    read -r _ u n s i w q sq st _ < /proc/stat
    total=$((u + n + s + i + w + q + sq + st)); idle=$((i + w))
    cpu=0
    if (( prev_total > 0 && total > prev_total )); then
        cpu=$(( 100 * ((total - prev_total) - (idle - prev_idle)) / (total - prev_total) ))
    fi
    prev_total=$total; prev_idle=$idle

    read -r mem_total mem_avail < <(awk '/^MemTotal:/{t=$2} /^MemAvailable:/{a=$2} END{print t*1024, a*1024}' /proc/meminfo)
    read -r rx tx < <(awk 'NR>2 { sub(/^ +/, ""); split($0, a, /[: ]+/); if (a[1] != "lo") { rx += a[2]; tx += a[10] } } END { print rx+0, tx+0 }' /proc/net/dev)
    rxr=0; txr=0
    if (( prev_rx > 0 )); then rxr=$((rx - prev_rx)); txr=$((tx - prev_tx)); fi
    (( rxr < 0 )) && rxr=0; (( txr < 0 )) && txr=0
    prev_rx=$rx; prev_tx=$tx

    if (( tick % 2 == 0 )); then read_gpu; temp=$(cpu_temp); fi
    tick=$((tick + 1))

    printf '{"cpu":%d,"ramUsed":%d,"ramTotal":%d,"gpu":%s,"vramUsed":%s,"vramTotal":%s,"temp":%s,"rx":%d,"tx":%d}\n' \
        "$cpu" "$((mem_total - mem_avail))" "$mem_total" "${gpu:--1}" "${vram_used:--1}" "${vram_total:--1}" "${temp:--1}" "$rxr" "$txr"
    sleep 1
done
