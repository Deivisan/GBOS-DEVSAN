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
| 0 | Fork + inventário + gate SHA-NI + detect AMD | **feito** (commits `16492e2`, `ceaf1eb`) |
| 0.5 | Espaço de instalação no `D:`: encolhido em 48 GB, ESP `GBOS_EFI` (512 MB) criada, 47,5 GB não alocados | **feito** (2026-11-15) |
| 1 | Build do stick nesta máquina (WSL2 + docker, `./build.sh` opção **3**) | `dist/gbOS86-*.img` gerado |
| 2 | Boot **live em RAM** no PC, monitor na iGPU | chega ao desktop (ou logs em `gbos/logs/boot-N/`) |
| 3 | Coletar `hwdetect.txt`, `stage0-dmesg.txt`, `logcat.txt*`, `display.txt` | evidência suficiente para decidir GPU/áudio |
| 4 | RADV estável (gralloc + HWC + cursor) | apps abrem sem crash-loop |
| 5 | Áudio pelo codec onboard | som nos speakers/line-out |
| 6 | Instalar no disco (`INSTALL_DISK=sda`, dual-boot nos 47,5 GB) + entrada de boot | boot sem stick, `/data` persistente |

### Fase 1: o build real neste host (2026-11-15)

Imagem gerada: `dist/gbOS86-20261115.img` — 6,3 GB, ESP 256M + GBOS 6G, sha256
`86d137ed…`, kernel 33,5 MB na ESP, `super.img` 3,44 GiB no `gbos/`.

Cinco armadilhas custaram tempo, todas de **host Windows**, nenhuma do projeto:

| Sintoma | Causa | Fix no fork |
|---|---|---|
| `set: Illegal option -` | checkout Windows com CRLF (o repo é feito pra Linux) | `.gitattributes` + `core.autocrlf=false` (commit `ceaf1eb`, `54c1d9c`) |
| `curl: (3) URL rejected` | `lapis/BUILD` sem extensão ficou CRLF → URL com `\r` | idem (arquivo listado no `.gitattributes`) |
| `EXIT=1` no menu | `printf '3\ny\n' \| sh build.sh`: o `read` do dash bufferiza e o 2º read vê EOF | usar `--standard --yes` |
| `docker is installed but not running` | engine do Docker Desktop cai; integração WSL nunca esteve ligada | `settings-store.json`: `integratedWslDistros=["Ubuntu"]`, `wslEngineEnabled=true` |
| `CP .../busybox: No such file` e `mcopy .../efi/EFI: No such file` | bind mount do Docker Desktop sobre `/mnt/c` entrega visão **vazia** ao container (nas duas direções) | `docker cp`/stdout pro busybox; `tools/make_gbos86_image_native.sh` pra imagem |

E uma de rede: link instável derrubou o download da imagem do Google com `curl: (92) HTTP/2 stream not closed`.
`fetch` agora força `--http1.1`, retenta tudo e **pula** arquivo cujo sha256 já confere. O primeiro trecho tinha
vindo por Wi-Fi e morreu em BSOD deixando **312 MB corrompidos** entre 1,74 e 2,06 GB; localizei comparando
janelas de 8 KB com `Range` do servidor e baixei só esse span, em vez dos 7,2 GB inteiros.

### Fase 1: o que o `--dry-run` já disse (2026-11-15)

```
This will download:
  - Google's recovery image: https://dl.google.com/device/recovery/lapis-user/16693588/recovery.zip (7.7 GB)
  - busybox-static from Debian via docker (about 1 MB)
  - gbos86-modules-6.18.21-gbos-whl-r5.tar.xz (14 MB, release do projeto)
  - gbos86-firmware-12dfe670-sof2026.09.2-r4.tar.xz (70 MB, release do projeto)
  - gbos86-swr-r1.tar.xz (software GPU driver for AMD graphics, 6 MB, release)
  - KernelSU_v3.3.1_32680-release.apk + ksud (19 MB, release do KernelSU)
```

**7,81 GB no total e nenhum kernel é compilado** (módulos e firmware vêm prontos do release): o custo é quase
todo download, ~30-60 min. Escolher a opção **3 (Standard generic live USB installer, `MODE=ask`)** — a opção 2
pré-configura `/dev/sda` a partir do `/dev/sda` do **WSL**, que não é o disco físico.

RADV **não** vem nesse download (só SwiftShader): o `GPU_VULKAN=auto` do boot cai para SwiftShader até rodarmos
`tools/radv-android/build.sh` (fase 4).

### Comandos da fase 1 (a rodar dentro do WSL, não no PowerShell)

```
# daemon do Docker Desktop precisa estar rodando
cd /mnt/c/Projetos/GBOS-DEVSAN
sh build.sh          # escolher 3
```

Depois: `dist/gbOS86-*.img` → gravar no pendrive com Rufus/balenaEtcher, boot por F12, Secure Boot off.

## Gravação da imagem no Windows (o que funcionou)

O WSL não anexa mídia removível (`wsl --mount` devolve `0x8007000f`), então a escrita crua sai do
PowerShell em `\\.\PhysicalDriveN`. Três detalhes custaram tempo até a gravação passar:

1. **`Clear-Disk -RemoveData -RemoveOEM` antes de abrir o device.** Setor que pertence a um volume
   montado — mesmo sem letra atribuída — devolve `Access denied` na escrita crua. Foi por isso que as
   primeiras tentativas gravavam só os 257 MB iniciais (GPT + ESP, sem volume) e nada depois.
2. **`FileStream` comum não serve.** `Flush()` não emite `FlushFileBuffers` num handle de dispositivo:
   as escritas ficam no cache do Windows, a releitura devolve o conteúdo antigo e o sha256 não bate.
   Abrir com `[System.IO.FileOptions]::WriteThrough` e chamar `FlushFileBuffers` via kernel32.
3. **Blocos de 16 MB, `FlushFileBuffers` por bloco**: 6.402 MB em 21,7 s (~296 MB/s). Blocos de 32 MB
   travaram no primeiro write — o handle fica esperando o serviço VDS terminar o `Clear-Disk`.

Verificação: SHA256 da releitura crua do device contra `Get-FileHash` da imagem. Bateu
(`86d137edeb0cb57171453598f557123fbfa1dbdf1d9b329e0c51c041b5b289ee`).

**A porta USB importa.** Com a gaveta USB-SATA numa porta frontal/hub o link resetava sob escrita
contínua — `disk` Event 153 (`E/S repetida no LBA`) seguido de `UASPStor` Event 129
(`Redefinir para dispositivo, \Device\RaidPort8`) — e a gravação morria entre 257 MB e 2,5 GB.
Na porta traseira, direto na placa-mãe, passou sem um único reset.

## Limites que eu não vou furar

- Não apago nem reparticiono disco sem o usuário digitar o serial (regra do `AGENTS.md`).
- Não baixo imagem/firmware do Google sem avisar tamanho e origem.
- Sem Wi-Fi/DW1530, sem touchpad/bateria (é desktop, não tem), sem GPU discreta como saída principal.
