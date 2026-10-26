# 🌡️ TermalGuard 2.0

**TermalGuard 2.0** es un módulo de código abierto para **KernelSU / KernelSU Next / Magisk** que proporciona control térmico inteligente y dinámico sobre la **CPU**, **GPU** y **Batería** en dispositivos Android con procesadores Qualcomm Snapdragon (optimizado para **Snapdragon 8 Gen 3 / SM8650** en HyperOS), incluyendo una **WebUI interactiva a 60 FPS** en tiempo real.

---

## ✨ Características Principales

- **Algoritmo de Interpolación Lineal por Ventana Anticipada**: A diferencia de los termostatos tradicionales que recortan frecuencias bruscamente al alcanzar el límite térmico, **TermalGuard 2.0** crea una rampa progresiva que comienza antes del límite configurado y escala grado por grado, liberando potencia inmediatamente cuando baja la temperatura.
- **Doble Sensor Independiente (CPU + Batería)**: Evalúa simultáneamente la temperatura del SoC (`thermal_zone57`) y de la batería (`battery/temp`), aplicando siempre el porcentaje más estricto e informando cuál es el factor limitante activo (`CPU`, `BATT` o `NONE`).
- **Dos Perfiles Térmicos en Tiempo Real**:
  - ⚙️ **Modo Sostenido (`sustained`)**: Piso mínimo de rendimiento del **35%**. Diseñado para sesiones prolongadas de juego y fluidez constante sin caídas bruscas de FPS.
  - 🔥 **Modo Agresivo (`aggressive`)**: Piso mínimo de rendimiento del **20%**. Diseñado para enfriar el dispositivo rápidamente bajo cargas extremas.
- **Bypass y Sincronización con HyperOS (`mi_thermald`)**: Sincroniza simultáneamente los nodos `scaling_max_freq` de cada clúster con `/sys/class/thermal/thermal_message/cpu_limits` y `cpu_nolimit_temp`, evitando que el demonio nativo de Xiaomi bloquee las frecuencias.
- **Escalado de GPU Adreno**: Ajusta dinámicamente tanto `devfreq/max_freq` como `max_gpuclk` seleccionando el escalón físico exacto de la GPU Adreno.
- **WebUI Integrada para KernelSU Next**:
  - Métricas en vivo cada 2 segundos (Temperatura de CPU, Temperatura de Batería, Porcentaje de Rendimiento y Factor Limitante).
  - Barras deslizantes a **60 FPS** con filtro inteligente anti-scroll vertical y previsualización instantánea.
  - Botón de reinicio de servicio y consola de registro en vivo.

---

## 🧠 ¿Cómo Funciona el Módulo?

### 1. Arquitectura de Hardware Controlada
El demonio (`thermal_guard.sh`) ejecuta un ciclo de control cada **2 segundos** sobre todos los clústeres de CPU y la GPU:

- **CPU (`cpufreq`)**:
  - **Policy 0** (Núcleos 0–1, Eficiencia Cortex-A520): hasta `2,265.6 MHz`
  - **Policy 2** (Núcleos 2–4, Rendimiento Medio Cortex-A720): hasta `3,148.8 MHz`
  - **Policy 5** (Núcleos 5–6, Rendimiento Alto Cortex-A720): hasta `2,956.8 MHz`
  - **Policy 7** (Núcleo 7, Prime Cortex-X4): hasta `3,302.4 MHz`
- **GPU (Adreno 750 - `kgsl-3d0`)**:
  - Escalones físicos desde `231 MHz` hasta `903 MHz` (`903000000 Hz`).
- **Sensores**:
  - **CPU**: `/sys/class/thermal/thermal_zone57/temp` (miligrados Celsius, dividido entre `1000`).
  - **Batería**: `/sys/class/power_supply/battery/temp` (décimas de grado Celsius, dividido entre `10`).

---

### 2. Algoritmo Matemático de Escalado Térmico

En cada ciclo, el módulo lee los límites configurados por el usuario en la WebUI:
- `LIMIT` (Límite de CPU, entre `40 °C` y `85 °C`, por defecto `65 °C`)
- `BATT_LIMIT` (Límite de Batería, entre `35 °C` y `50 °C`, por defecto `42 °C`)
- `PROFILE` (`sustained` o `aggressive`)

#### Parámetros por Perfil

| Parámetro | ⚙️ Modo Sostenido (`sustained`) | 🔥 Modo Agresivo (`aggressive`) |
| :--- | :---: | :---: |
| **Piso mínimo (`MIN_PCT`)** | `35%` | `20%` |
| **Rango recortable (`RANGE_PCT`)** | `65%` | `80%` |
| **Ventana CPU (`START_OFFSET` / `END_OFFSET`)** | `-8 °C` a `+12 °C` (`SPAN = 20 °C`) | `-10 °C` a `+20 °C` (`SPAN = 30 °C`) |
| **Pendiente de recorte CPU** | `3.25%` por cada `1 °C` | `2.66%` por cada `1 °C` |
| **Ventana Batería (`B_START_OFFSET` / `B_END_OFFSET`)** | `-3 °C` a `+4 °C` (`B_SPAN = 7 °C`) | `-4 °C` a `+6 °C` (`B_SPAN = 10 °C`) |
| **Pendiente de recorte Batería** | `9.28%` por cada `1 °C` | `8.00%` por cada `1 °C` |

#### Ecuaciones Paso a Paso

1. **Cálculo del porcentaje permitido por CPU (`CPU_PCT`)**:
   ```text
   RSTART = LIMIT - START_OFFSET
   REND   = LIMIT + END_OFFSET
   SPAN   = REND - RSTART

   Si TEMP <= RSTART  --> CPU_PCT = 100%
   Si TEMP >= REND    --> CPU_PCT = MIN_PCT
   Si RSTART < TEMP < REND:
       DIFF    = TEMP - RSTART
       DROP    = (DIFF * RANGE_PCT) / SPAN
       CPU_PCT = 100 - DROP
   ```

2. **Cálculo del porcentaje permitido por Batería (`BATT_PCT`)**:
   ```text
   B_RSTART = BATT_LIMIT - B_START_OFFSET
   B_REND   = BATT_LIMIT + B_END_OFFSET
   B_SPAN   = B_REND - B_RSTART

   Si BATT_TEMP <= B_RSTART  --> BATT_PCT = 100%
   Si BATT_TEMP >= B_REND    --> BATT_PCT = MIN_PCT
   Si B_RSTART < BATT_TEMP < B_REND:
       B_DIFF   = BATT_TEMP - B_RSTART
       B_DROP   = (B_DIFF * RANGE_PCT) / B_SPAN
       BATT_PCT = 100 - B_DROP
   ```

3. **Selección del Factor Limitante (`REASON`)**:
   - Si `CPU_PCT == 100` y `BATT_PCT == 100` → `PCT = 100%` (`REASON = NONE`)
   - Si `BATT_PCT < CPU_PCT` → `PCT = BATT_PCT` (`REASON = BATT`)
   - En caso contrario → `PCT = CPU_PCT` (`REASON = CPU`)

---

### 3. Aplicación en el Kernel y Bypass de HyperOS

Una vez obtenido el porcentaje `PCT`:

1. **Desbloqueo del umbral térmico de HyperOS**:
   Escribe `85000` en `/sys/class/thermal/thermal_message/cpu_nolimit_temp`.
2. **Escalado proporcional por clúster de CPU**:
   Para cada `policyX`, calcula `TARGET = (cpuinfo_max_freq / 100) * PCT` y lo escribe tanto en:
   - `/sys/devices/system/cpu/cpufreq/policyX/scaling_max_freq`
   - `/sys/class/thermal/thermal_message/cpu_limits` (`cpuX TARGET`)
3. **Escalado de GPU**:
   Calcula `GPU_RAW = (903000000 / 100) * PCT`, selecciona el escalón físico válido inmediatamente inferior o igual (`pick_gpu_freq`) y lo aplica en:
   - `/sys/class/kgsl/kgsl-3d0/devfreq/max_freq`
   - `/sys/class/kgsl/kgsl-3d0/max_gpuclk`

---

## 📂 Estructura del Proyecto

```text
termalguard-2.0/
├── customize.sh         # Verificador de dispositivo (exclusivo para POCO F7 Pro) e instalador
├── module.prop          # Metadatos del módulo (TermalGuard 2.0)
├── service.sh           # Script de arranque post-boot (inicia el demonio con nohup)
├── thermal_guard.sh     # Demonio principal de control térmico (ciclo de 2s)
├── uninstall.sh         # Limpieza y restauración de frecuencias de fábrica al desinstalar
├── webroot/
│   └── index.html       # Panel de control WebUI interactivo para KernelSU / KernelSU Next
└── termal_2.0.txt       # Documentación técnica detallada y cálculos matemáticos
```

---

## 🚀 Instalación y Uso

> **⚠️ Requisito de Dispositivo**: Este módulo verifica durante la instalación (`customize.sh`) que el dispositivo sea exclusivamente un **POCO F7 Pro** (`zorn` / `24117RK2CG`). Si detecta cualquier otro modelo, la instalación se cancelará automáticamente para proteger el hardware.

1. Descarga el archivo `.zip` desde la sección de **Releases** (o comprime el contenido del repositorio en un archivo ZIP desde la raíz del módulo).
2. Abre **KernelSU Next**, **KernelSU** o **Magisk** e instala el archivo `.zip` como módulo.
3. Reinicia tu dispositivo.
4. Abre la **WebUI** de **TermalGuard 2.0** desde tu gestor root para:
   - Elegir entre el perfil **Sostenido** o **Agresivo**.
   - Ajustar en vivo el límite de temperatura de **CPU** (`40 °C – 85 °C`) y **Batería** (`35 °C – 50 °C`).
   - Monitorear la temperatura, el porcentaje de rendimiento y el factor limitante en tiempo real.

---

## 📄 Licencia

Distribuido bajo la licencia **MIT**. Código completamente abierto para la comunidad.
