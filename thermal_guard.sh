#!/system/bin/sh
trap '' HUP

PIDFILE=/data/local/tmp/thermal_guard.pid
LOG=/data/local/tmp/thermal_guard.log
CONF=/data/local/tmp/thermal_guard.conf
BATT_CONF=/data/local/tmp/thermal_guard_batt.conf
PROFILE_CONF=/data/local/tmp/thermal_guard_profile.conf

ZONE_TEMP=/sys/class/thermal/thermal_zone57/temp
BATT_NODE=/sys/class/power_supply/battery/temp
GPU_MAXF=903000000
GPU_NODE=/sys/class/kgsl/kgsl-3d0/devfreq/max_freq
GPU_CLK_NODE=/sys/class/kgsl/kgsl-3d0/max_gpuclk
CPU_LIM_NODE=/sys/class/thermal/thermal_message/cpu_limits
NOLIMIT_NODE=/sys/class/thermal/thermal_message/cpu_nolimit_temp

DEFAULT_LIMIT=65
DEFAULT_BATT_LIMIT=42
DEFAULT_PROFILE=sustained

if [ "$1" = "restart" ]; then
  if [ -f "$PIDFILE" ]; then
    OLD_PID=$(cat "$PIDFILE" 2>/dev/null)
    if [ -n "$OLD_PID" ] && [ "$OLD_PID" != "$$" ] && [ "$OLD_PID" != "$PPID" ]; then
      kill -9 "$OLD_PID" 2>/dev/null
    fi
    rm -f "$PIDFILE"
  fi
fi

if [ -f "$PIDFILE" ]; then
  EXISTING_PID=$(cat "$PIDFILE" 2>/dev/null)
  if [ -n "$EXISTING_PID" ] && [ "$EXISTING_PID" != "$$" ] && kill -0 "$EXISTING_PID" 2>/dev/null; then
    exit 0
  fi
fi

echo $$ > "$PIDFILE"
chmod 0666 "$PIDFILE" 2>/dev/null
exec </dev/null >/dev/null 2>&1

[ -f "$CONF" ] || echo "$DEFAULT_LIMIT" > "$CONF"
[ -f "$BATT_CONF" ] || echo "$DEFAULT_BATT_LIMIT" > "$BATT_CONF"
[ -f "$PROFILE_CONF" ] || echo "$DEFAULT_PROFILE" > "$PROFILE_CONF"
chmod 0666 "$CONF" "$BATT_CONF" "$PROFILE_CONF" 2>/dev/null

# Escalon valido de GPU mas cercano (<= target)
pick_gpu_freq() {
  req=$1
  for f in 903000000 834000000 770000000 720000000 680000000 629000000 578000000 500000000 422000000 366000000 310000000 231000000; do
    if [ "$f" -le "$req" ]; then
      echo "$f"
      return
    fi
  done
  echo 231000000
}

LOOP_COUNT=0

while true; do
  LIMIT=$(cat "$CONF" 2>/dev/null | tr -d ' \t\r\n')
  case "$LIMIT" in
    ''|*[!0-9]*) LIMIT=$DEFAULT_LIMIT ;;
  esac
  [ "$LIMIT" -lt 40 ] && LIMIT=40
  [ "$LIMIT" -gt 85 ] && LIMIT=85

  BATT_LIMIT=$(cat "$BATT_CONF" 2>/dev/null | tr -d ' \t\r\n')
  case "$BATT_LIMIT" in
    ''|*[!0-9]*) BATT_LIMIT=$DEFAULT_BATT_LIMIT ;;
  esac
  [ "$BATT_LIMIT" -lt 35 ] && BATT_LIMIT=35
  [ "$BATT_LIMIT" -gt 50 ] && BATT_LIMIT=50

  PROFILE=$(cat "$PROFILE_CONF" 2>/dev/null | tr -d ' \t\r\n')

  if [ "$PROFILE" = "sustained" ]; then
    START_OFFSET=8
    END_OFFSET=12
    B_START_OFFSET=3
    B_END_OFFSET=4
    MIN_PCT=35
  else
    PROFILE=aggressive
    START_OFFSET=10
    END_OFFSET=20
    B_START_OFFSET=4
    B_END_OFFSET=6
    MIN_PCT=20
  fi

  TEMP_RAW=$(cat "$ZONE_TEMP" 2>/dev/null)
  [ -z "$TEMP_RAW" ] && { sleep 2; continue; }
  TEMP=$((TEMP_RAW / 1000))

  BATT_RAW=$(cat "$BATT_NODE" 2>/dev/null)
  if [ -n "$BATT_RAW" ]; then
    BATT_TEMP=$((BATT_RAW / 10))
  else
    BATT_TEMP=35
  fi

  RANGE_PCT=$((100 - MIN_PCT))

  # 1. Calculo lineal de CPU
  RSTART=$((LIMIT - START_OFFSET))
  REND=$((LIMIT + END_OFFSET))
  SPAN=$((REND - RSTART))
  [ "$SPAN" -le 0 ] && SPAN=1

  if [ "$TEMP" -le "$RSTART" ]; then
    CPU_PCT=100
  elif [ "$TEMP" -ge "$REND" ]; then
    CPU_PCT=$MIN_PCT
  else
    DIFF=$((TEMP - RSTART))
    DROP=$(( (DIFF * RANGE_PCT) / SPAN ))
    CPU_PCT=$((100 - DROP))
  fi

  # 2. Calculo lineal de Bateria
  B_RSTART=$((BATT_LIMIT - B_START_OFFSET))
  B_REND=$((BATT_LIMIT + B_END_OFFSET))
  B_SPAN=$((B_REND - B_RSTART))
  [ "$B_SPAN" -le 0 ] && B_SPAN=1

  if [ "$BATT_TEMP" -le "$B_RSTART" ]; then
    BATT_PCT=100
  elif [ "$BATT_TEMP" -ge "$B_REND" ]; then
    BATT_PCT=$MIN_PCT
  else
    B_DIFF=$((BATT_TEMP - B_RSTART))
    B_DROP=$(( (B_DIFF * RANGE_PCT) / B_SPAN ))
    BATT_PCT=$((100 - B_DROP))
  fi

  # 3. Seleccion del factor limitante mas estricto
  if [ "$CPU_PCT" -eq 100 ] && [ "$BATT_PCT" -eq 100 ]; then
    PCT=100
    REASON="NONE"
  elif [ "$BATT_PCT" -lt "$CPU_PCT" ]; then
    PCT=$BATT_PCT
    REASON="BATT"
  else
    PCT=$CPU_PCT
    REASON="CPU"
  fi

  # 4. Aplicacion en CPU + HyperOS thermal_message
  if [ -f "$NOLIMIT_NODE" ]; then
    echo 85000 > "$NOLIMIT_NODE" 2>/dev/null
  fi

  for POLICY in /sys/devices/system/cpu/cpufreq/policy*; do
    MAXF=$(cat "$POLICY/cpuinfo_max_freq" 2>/dev/null)
    [ -z "$MAXF" ] && continue
    TARGET=$(( (MAXF / 100) * PCT ))
    chmod 644 "$POLICY/scaling_max_freq" 2>/dev/null
    echo "$TARGET" > "$POLICY/scaling_max_freq" 2>/dev/null
    POL_NUM=${POLICY##*policy}
    if [ -f "$CPU_LIM_NODE" ]; then
      echo "cpu${POL_NUM} ${TARGET}" > "$CPU_LIM_NODE" 2>/dev/null
    fi
  done

  # 5. Aplicacion en GPU (devfreq/max_freq y max_gpuclk)
  GPU_RAW=$(( (GPU_MAXF / 100) * PCT ))
  GPU_TARGET=$(pick_gpu_freq "$GPU_RAW")
  if [ -f "$GPU_NODE" ]; then
    chmod 644 "$GPU_NODE" 2>/dev/null
    echo "$GPU_TARGET" > "$GPU_NODE" 2>/dev/null
  fi
  if [ -f "$GPU_CLK_NODE" ]; then
    chmod 644 "$GPU_CLK_NODE" 2>/dev/null
    echo "$GPU_TARGET" > "$GPU_CLK_NODE" 2>/dev/null
  fi

  echo "$(date '+%H:%M:%S') temp=${TEMP}C batt=${BATT_TEMP}C limit=${LIMIT}/${BATT_LIMIT}C profile=${PROFILE} pct=${PCT}% reason=${REASON}" >> "$LOG"
  chmod 0666 "$LOG" 2>/dev/null

  LOOP_COUNT=$((LOOP_COUNT + 1))
  if [ "$LOOP_COUNT" -ge 80 ]; then
    tail -n 40 "$LOG" > "${LOG}.tmp" 2>/dev/null && mv "${LOG}.tmp" "$LOG" 2>/dev/null
    chmod 0666 "$LOG" 2>/dev/null
    LOOP_COUNT=0
  fi

  sleep 2
done
