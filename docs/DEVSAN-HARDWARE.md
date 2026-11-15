# GBOS DEVSAN: hardware alvo

Inventário medido da máquina em que este fork roda e para a qual ele é portado.
Medido em **2026-11-15**; qualquer mudança (peça trocada, BIOS atualizada) deve atualizar este arquivo.

## Resumo

| | |
|---|---|
| Placa | ASUS PRIME B450M-GAMING/BR (socket AM4, chipset B450) |
| Firmware | AMI 4645, **UEFI**, **Secure Boot desligado** (o gbOS86 exige isso) |
| CPU | AMD Ryzen 7 5700G (Cezanne, **Zen 3**), 8 núcleos / 16 threads |
| RAM | 33,6 GB (31,3 GB visíveis no Windows) |
| GPU que desenha | **AMD Radeon iGPU `1002:1638`** (Cezanne/Vega, GFX9), 1920x1080 |
| GPU secundária | AMD Radeon RX 550X `1002:699F` (Polaris 12, GFX8, 4 GB), sem monitor |
| Áudio | HDA onboard Realtek (ALC887 na B450M) + HDA HDMI das duas GPUs |
| Rede | Ethernet Realtek RTL8168 (r8169) · Wi-Fi DW1530 (Broadcom BCM4322) |
| Discos | NVMe 238 GB (Windows, `C:`) · SATA 224 GB Kingston (`D:`) |

## CPU: o que é nativo e o que vai ser emulado

Medido por CPUID direto no host (não pelo `/proc/cpuinfo` do WSL, que mascara features):

| Extensão | 5700G (Zen 3) | Consequência no gbOS86 |
|---|---|---|
| AVX / AVX2 / FMA / BMI2 | **nativo** | passa o `REQUIRE_AVX=1`; init/linker do AOSP rodam |
| SHA-NI | **nativo** | patch de `libcrypto` é **pessimização** aqui → as linhas `libcrypto` do MANIFEST são puladas (ver `usb/hook.sh`) |
| VAES / VPCLMULQDQ (256-bit) | **nativo** | AES/GCM do BoringSSL e boa parte do zlib rodam na CPU |
| GFNI | **ausente** | emulado no `#UD` do kernel (`kernel/isa_emu_patch`) |
| AVX-VNNI | **ausente** | emulado; é o motivo do patch de `libz` (`vpdpwssd` em `adler32_z`) continuar necessário |
| AVX-IFMA | **ausente** | emulado |
| AVX-512 (toda a família) | **ausente** | emulado/evitado; mesmas lacunas conhecidas do projeto upstream |

Comparação: a máquina de referência do projeto (Dell Latitude 5300, i5-8365U) não tem nenhuma das quatro
extensões e emula tudo. Aqui só GFNI/VNNI/IFMA são emulados, então o porte deve ficar **mais rápido** que na
referência.

## GPU

O monitor está na **iGPU Cezanne (`1002:1638`)** — mesma família GFX9/RENOIR em que o upstream já chegou ao
desktop com RADV (MSI Modern 15 B7M, `1002:15e7`). A RX 550X (Polaris, GFX8) existe mas não alimenta a tela;
serve no máximo como segundo display.

Não existe GPU Intel: o modo `GPU_SOFTWARE=auto` do `hook.sh` liga o caminho AMD
(gralloc com backend `amdgpu` + RADV/SwiftShader no lugar do `vulkan.intel.so`).

## Áudio

Placa com HDA legado (não é SOF, não é SoundWire): caminho mais simples que o dos laptops novos. Mas no Linux
as **duas** controladoras aparecem como `Generic` (a GPU, codec "ATI R6xx HDMI") e `Generic_1` (o codec
Realtek), que é exatamente o caso já tratado em `gbos_audio_card` e `usb/audio/gen_config.sh`.
Risco real: o HAL `dras` do Google ainda não reconhece o cartão em algumas máquinas AMD
(ver `HANDOFF.md`, Acer A515-46: `AlsaCardManager::init succeeded but internal card not found`).

## Rede

- **Ethernet Realtek RTL8168**: `r8169` + firmware `rtl_nic` já estão no build → é o caminho de rede do porte.
- **Wi-Fi DW1530 (BCM4322)**: é FullMAC antigo, coberto por `b43`/`ssb`, não por `brcmfmac`. Exigiria firmware
  extraído do driver proprietário (`b43-fwcutter`) e um módulo que o build não traz. **Fora de escopo** por ora.

## Armazenamento e instalação

Hoje os dois discos estão com 100% do espaço alocado (NVMe: `C:` de 237,5 GB; SATA: `D:` de 223,6 GB), sem
espaço não alocado. O instalador do gbOS86:

- prefere NVMe; para usar o SATA (Kingston) é preciso `INSTALL_DISK=sda` no `gbos.cfg`;
- em dual-boot **não** mexe nas partições existentes, só usa espaço **não alocado** (≥ 24 GB recomendado);
- exige o disco em modo **AHCI** no BIOS (não RST/RAID/VMD — o kernel não tem `CONFIG_VMD`).

Ou seja: instalar de verdade exige encolher `C:` (Gerenciamento de Disco → Encolher Volume, ≥ 24 GB) ou aceitar
um install limpo. Até lá, **live USB em RAM** (`MODE=live`) valida tudo sem tocar em disco.

## Ambiente de build nesta máquina

| | |
|---|---|
| Docker | 29.9.2 (Docker Desktop; daemon precisa estar rodando) |
| WSL2 | Ubuntu, VHD com ~955 GB livres internos |
| Disco do host | `C:` com ~92 GB livres — o build pede ~35 GB (7,7 GB da imagem do Google + imagem gerada) |
| Ferramentas | `python3` (mise), `curl`, `tar`, `xz`, `sha256sum`, gcc (mingw, fora do WSL) |
