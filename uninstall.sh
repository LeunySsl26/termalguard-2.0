#!/system/bin/sh
PIDFILE=/data/local/tmp/thermal_guard.pid
if [ -f "$PIDFILE" ]; then
  OLD_PID=$(cat "$PIDFILE" 2>/dev/null)
  [ -n "$OLD_PID" ] && kill -9 "$OLD_PID" 2>/dev/null
  rm -f "$PIDFILE"
fi

for POLICY in /sys/devices/system/cpu/cpufreq/policy*; do
  MAXF=$(cat "$POLICY/cpuinfo_max_freq" 2>/dev/null)
  [ -z "$MAXF" ] && continue
  chmod 644 "$POLICY/scaling_max_freq" 2>/dev/null
  echo "$MAXF" > "$POLICY/scaling_max_freq" 2>/dev/null
  POL_NUM=${POLICY##*policy}
  if [ -f /sys/class/thermal/thermal_message/cpu_limits ]; then
    echo "cpu${POL_NUM} ${MAXF}" > /sys/class/thermal/thermal_message/cpu_limits 2>/dev/null
  fi
done

if [ -f /sys/class/kgsl/kgsl-3d0/devfreq/max_freq ]; then
  chmod 644 /sys/class/kgsl/kgsl-3d0/devfreq/max_freq 2>/dev/null
  echo 903000000 > /sys/class/kgsl/kgsl-3d0/devfreq/max_freq 2>/dev/null
fi
if [ -f /sys/class/kgsl/kgsl-3d0/max_gpuclk ]; then
  chmod 644 /sys/class/kgsl/kgsl-3d0/max_gpuclk 2>/dev/null
  echo 903000000 > /sys/class/kgsl/kgsl-3d0/max_gpuclk 2>/dev/null
fi

rm -f /data/local/tmp/thermal_guard.pid \
      /data/local/tmp/thermal_guard.log \
      /data/local/tmp/thermal_guard.conf \
      /data/local/tmp/thermal_guard_batt.conf \
      /data/local/tmp/thermal_guard_profile.conf
