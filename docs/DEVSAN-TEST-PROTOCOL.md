# Protocolo de teste em hardware (DEVSAN)

O que fazer no primeiro boot e **exatamente** o que procurar nos logs. Sem isso, "não abriu o desktop" não vira
diagnóstico. Tudo o que o sistema produz fica na própria partição do stick: `GBOS/gbos/logs/boot-N/`.

## 0. O que a imagem pode (e não pode) fazer com os discos internos

Auditado no `install.sh` e no `usb/stage0_init.sh` antes do primeiro boot, porque a pergunta é justa: um stick
bootável com instalador pode apagar o disco do Windows.

- **Menu (`MODE=ask`)**: 15 s de timeout e o default é `1) Run gbOS86 live from this USB`. A opção `3) Boot the
  installed gbOS86` só aparece — e só vira default — quando existe `GBOSSYS` num disco interno. Aqui não existe.
- **Escolha 1 (live)**: `FROM=stick`, então `/data` e `/metadata` são **tmpfs**. A busca por partição ext4 interna
  (`find_part GBOS_DATA`) só roda com `FROM=nvme`. Nada em disco interno é montado rw nem formatado.
- **Escolha 2 (install)**: exige *instalar* de verdade. Mostra modelo/serial do alvo, lista as partições que serão
  perdidas, pede `1) Dual-Boot / 2) Full clean install / 3) Live` e, no caso 2, **exige digitar o serial exato do
  disco**. Nada é escrito antes disso.
- **`mkfs`/`sfdisk --wipe`/`dd of=` só existem dentro de `install.sh`** — nenhum outro script da imagem toca partição.
  O "fake ChromeOS boot disk" do `hook.sh` é um `bootdisk.img` num loop device em RAM (`/dev/loop6`).
- **Risco real, e é humano**: com dois discos internos o instalador **não recusa** — lista e pergunta
  `Choose target disk [1-N, default: 1]`, e o default é o NVMe (`nvme0n1`) do Windows. Ou seja: opção 2 + Enter +
  Enter + serial digitado = Windows apagado. Não usar a opção 2 nesta máquina até existir plano de dualboot
  consciente (`INSTALL_DISK` no `gbos.cfg`).

## 1. Gravar e bootar

1. Imagem: `dist/gbOS86-*.img` (padrão: ESP 256 MiB + `GBOS` 6 GiB ≈ 6,3 GB → pendrive de **8 GB ou mais**).
2. Gravar com **Rufus** (modo "DD") ou balenaEtcher. Secure Boot já está desligado nesta máquina.
3. F12 no boot → escolher **UEFI: \<pendrive\>** (não a entrada legada).
4. Menu do gbOS86: escolher **1) Live from USB** (nada é gravado, roda em RAM).

## 2. Sinais que confirmam o porte (antes de olhar a tela)

Do `gbos/logs/boot-N/stage0-dmesg.txt`:

| Procurar | Esperado nesta máquina | Se não aparecer |
|---|---|---|
| `early: /new/system/lib64/libcrypto.so kept as Google built it` | **sim, 2 linhas** | o gate de SHA-NI não rodou; `GBOS_NATIVE_SHA=1` força |
| `PATCH-STATUS 3 applied, 0 not applied, 2 skipped (native SHA-NI)` | **sim** | se `not applied` > 0, o build do Google mudou: rodar `tools/port_build.sh` |
| `apex_patch: skipped lib64/libcrypto.so (CPU has native SHA-NI)` | **sim** | idem |
| `hook: software rendering: on (auto; ...)` | **sim** (não há GPU Intel) | se ausente, `amdgpu` não vinculou |
| `hook: software rendering: Vulkan driver (SwiftShader, CPU)` | **sim nesta fase** | RADV só depois de `tools/radv-android/build.sh` |
| `gralloc (libminigbm_gralloc, amdgpu backend) replaced` | **sim** | hash do original mudou → patch não aplica |
| `i915 load FAILED` | **esperado e inofensivo** (modprobe cego do stage0) | — |

Do `hwdetect.txt`, seção `== gpu`: `card0 … amdgpu`, blocos `[drm] Display Core`, DCN, VRAM, e nada em
`== missing firmware` sobre `amdgpu/*`.

## 3. Se o desktop não aparecer

Ordem de investigação, das causas que o upstream já viu em AMD:

1. `display.txt` → há plano (plane) ligado a crtc com `fb=`? Se sim, frames saem e o problema é composição.
2. `logcat.txt*` (atenção: `logcat.txt` é só o mais novo; os anteriores são `.01`, `.02`, ...):
   - `Plane[N] does not support COLOR_PIPELINE` / `No pipelines available` → regressão do fix de HWC;
   - `queueProps[i].queueFamilyProperties.queueCount` → HWUI Vulkan (deveria estar desligado em software mode);
   - `Fatal signal 6 (SIGABRT)` em `RenderThread` → crash-loop de app;
   - `drmhwc: Attaching connector` presente = bom sinal.
3. `kmsg.log` → `Linux version …-gbos-whl` (confirma kernel), `amdgpu` com reset/hang, `*ERROR*`.
4. Se estiver tudo lento: `RESOLUTION=` menor no `gbos.cfg` do stick.

## 4. Áudio (o risco #1)

`audio.txt` + `logcat.txt*`:

- bom: `audio config gbos-gen (card id Generic_1 ...)` e o HAL `dras` abrindo o cartão;
- ruim (visto em Acer A515-46): `AlsaCardManager::init succeeded but internal card not found; retrying` ×100,
  `AudioPolicyManager: 0x0`, `listAudioProductStrategies error -19`;
- nesse caso: guardar `audio_config.generated.xml` + as linhas `dras`, e usar saída USB como contorno.

## 5. Como trazer a evidência

No menu do stick: **2 (Install/update)** → **3 (Only save logs)**. Isso copia os últimos boots do disco interno
(já instalado) para o stick. Em modo live, os logs do boot atual já estão em `GBOS/gbos/logs/boot-N/`.

Depois é só plugar o stick aqui e eu leio `boot-N/`.
