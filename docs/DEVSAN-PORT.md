# GBOS DEVSAN: plano de porte

Fork `Deivisan/GBOS-DEVSAN` de `linuxkid473/gbos-x86`.
Objetivo: rodar o **Googlebook OS (build Android `lapis` do Google)** neste PC —
Ryzen 7 5700G (Zen 3) + Radeon Vega iGPU + B450M, conforme `docs/DEVSAN-HARDWARE.md`.

O upstream foi construído em cima de um **Dell Latitude 5300 (Intel Whiskey Lake, i915)**. Quase tudo que é
Intel-específico já foi **generalizado** por ele (coldplug por modalias, `hwdetect.sh`, módulos genéricos, e um
caminho AMD experimental). O trabalho aqui não é escrever um port do zero: é **validar o caminho AMD em
hardware real**, que o upstream marca explicitamente como `untested on hardware` em várias partes.

## O que o upstream já entrega pronto para AMD

| Peça | Onde | Estado upstream |
|---|---|---|
| Seleção de GPU não-Intel | `usb/hook.sh` (`gbos_gpu_software`, `gbos_gpu_vulkan`) | testado só em lógica/QEMU + 1 laptop Ryzen |
| gralloc com backend `amdgpu` | `tools/patch_gralloc_amdgpu.py` → `usb/patched/libminigbm_gralloc.amdgpu.so` | funciona (MSI B7M) |
| RADV como HAL Vulkan | `tools/radv-android/build.sh` → `usb/patched/vulkan.radv.so` | desktop estável em RENOIR (`1002:15e7`) |
| Drvs. HDA legado + codec Realtek | `usb/audio/gbos-hda-pch` + `usb/audio/gen_config.sh` | som funciona em Intel; **falha conhecida em AMD** |
| Módulos/firmware AMD | `tools/fetch_firmware.sh` (amdgpu, r8169, `rtl_nic`) | ok |
| Instalador NVMe/eMMC/SATA | `usb/install.sh` + `tools/install_dualboot.sh` | testado em QEMU, não em desktop AMD |

## Iteração 1 (este commit)

1. **SHA-NI nativo deixa de ser penalizado.** O patch de `libcrypto` do upstream redireciona SHA-NI para código
   escalar — necessário no i5-8365U (cada instrução caía no emulador), *mais lento* no Zen 3, que executa SHA-NI
   nativamente. Agora `usb/hook.sh`, `usb/early_patch.sh` e `usb/apex_patch.sh` detectam `sha_ni` no
   `/proc/cpuinfo` e pulam **só as linhas de libcrypto** do MANIFEST (o patch de `libz` continua, porque depende
   de AVX-VNNI, que este CPU não tem). Override: `GBOS_NATIVE_SHA=0|1`. Coberto em `tools/test_port_scripts.sh`.
2. **`tools/detect_hardware.sh` ciente de AMD.** Detecta vendor da CPU, lista o que é nativo vs. emulado
   (SHA-NI/GFNI/AVX-VNNI/AVX-IFMA/VAES/VPCLMULQDQ) e, quando não há cartão DRM no host de build
   (docker/WSL), cai para o vendor da CPU em vez de assumir Intel. Com isso `./build.sh --auto` nesta máquina
   produz `GPU_SOFTWARE=auto, GPU_VULKAN=radv, LOAD_I915=auto`.

## Riscos, em ordem de probabilidade

1. **Áudio (`dras`) não reconhecer o cartão AMD.** Já aconteceu em Acer A515-46 (Ryzen 3): `AlsaCardManager::init
   succeeded but internal card not found; retrying` ×100. O `gen_config.sh` gera o XML, mas o HAL pode recusar.
   Evidência a coletar: `audio_config.generated.xml` + linhas `dras` do `logcat.txt.01/.02`.
   Plano B: saída de áudio USB (o caminho HDA legado do kernel já funciona) enquanto o HAL não coopera.
2. **RADV/Vega + drm_hwcomposer.** O upstream já corrigiu `COLOR_PIPELINE` (amdgpu não tem a propriedade) e
   `ro.hwui.use_vulkan=false` (SwiftShader/RADV reportam 1 fila, HWUI quer ≥2). Restam relatos de **cursor como
   quadrado vermelho** e **Widevine com `Permission denied` em `/dev/dri/card0`** — nenhum impede o desktop.
3. **Primeiro boot demora.** SwiftShader compila shader em CPU a cada boot; com RADV é bem melhor. Se travar,
   baixar `RESOLUTION` no `gbos.cfg` é o botão de emergência.
4. **Instalação em disco.** Sem espaço não alocado hoje; dual-boot exige encolher `C:` (≥ 24 GB) e o SATA só é
   alvo com `INSTALL_DISK=sda`. Live USB em RAM não toca em nada e valida o resto primeiro.
5. **Sem Wi-Fi.** DW1530 é BCM4322 → `b43`/`ssb`, não `brcmfmac`. Rede por Ethernet (`r8169`).

## Roadmap

| Fase | O que | Critério de pronto |
|---|---|---|
| 0 | Fork + inventário + gate SHA-NI + detect AMD | **feito** (este commit) |
| 1 | Build do stick nesta máquina (WSL2 + docker, `./build.sh --auto`) | `dist/gbOS86-*.img` gerado |
| 2 | Boot **live em RAM** no PC, monitor na iGPU | chega ao desktop (ou logs em `gbos/logs/boot-N/`) |
| 3 | Coletar `hwdetect.txt`, `stage0-dmesg.txt`, `logcat.txt*`, `display.txt` | evidência suficiente para decidir GPU/áudio |
| 4 | RADV estável (gralloc + HWC + cursor) | apps abrem sem crash-loop |
| 5 | Áudio pelo codec onboard | som nos speakers/line-out |
| 6 | Instalar no disco (SATA ou espaço encolhido do NVMe) | boot sem stick, `/data` persistente |

### Comandos da fase 1 (a rodar dentro do WSL, não no PowerShell)

```
# daemon do Docker Desktop precisa estar rodando
cd /mnt/c/Projetos/GBOS-DEVSAN
./build.sh --dry-run      # mostra o que baixa (imagem do Google 7,7 GB, busybox, firmwares)
./build.sh --auto         # ~30-60 min, a maior parte download
```

Depois: `dist/gbOS86-*.img` → gravar no pendrive com Rufus/balenaEtcher (ou `dd`), boot por F12, Secure Boot off.

## Limites que eu não vou furar

- Não apago nem reparticiono disco sem o usuário digitar o serial (regra do `AGENTS.md`).
- Não baixo imagem/firmware do Google sem avisar tamanho e origem.
- Sem Wi-Fi/DW1530, sem touchpad/bateria (é desktop, não tem), sem GPU discreta como saída principal.
