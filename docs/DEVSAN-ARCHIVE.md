# GBOS-DEVSAN — estado final e como retomar

**Arquivado em 2026-11-15.** Este fork existe para rodar o gbOS86 num desktop AMD, não num laptop Intel.
Chegou a bootar. Parou por decisão do autor: o resultado ficou inutilizável e o projeto upstream ainda está
amadurecendo. Este arquivo é o que eu gostaria de ter encontrado ao retomar.

## Onde parou

| etapa | estado |
|---|---|
| Fork + remoto (`Deivisan/GBOS-DEVSAN`, upstream `linuxkid473/gbos-x86`) | feito |
| Inventário da máquina e análise de ISA (`docs/DEVSAN-HARDWARE.md`) | feito |
| Gate SHA-NI nos patches (`usb/hook.sh`, `early_patch.sh`, `apex_patch.sh`) | feito, não testado em hardware |
| `tools/detect_hardware.sh` ciente de AMD | feito, não testado em hardware |
| Correções de build no host Windows (`fetch()`, `.gitattributes`, `make_gbos86_image_native.sh`) | feito, usado no build real |
| Imagem `gbOS86-20261115.img` construída e gravada no SSD | feito, `SHA_OK` |
| Gravação confiável no Windows documentada (`docs/DEVSAN-PORT.md`) | feito |
| **Boot em modo live no hardware** | **bootou, inutilizável** (`docs/DEVSAN-BOOT-REPORT-01.md`) |
| RADV para a Vega (fase 4, `tools/radv-android/build.sh`) | **não feito** |
| Instalação em disco interno (dual-boot no Kingston SATA) | **não feito** |

## Duas causas prováveis da lentidão, ambas estruturais

1. **`/system` lendo de USB.** O modo live monta `super.img` (3,5 GB) por `losetup` a partir de um arquivo
   na partição **FAT32** do stick, e monta `erofs` por cima. Todo acesso a arquivo do sistema atravessa
   USB → FAT32 → loop → erofs, com leitura aleatória — o pior caso possível num SSD USB.
2. **Renderização na CPU.** `GPU_VULKAN=auto` só usa RADV se `gbos/patched/vulkan.radv.so` existir; sem ele
   o boot cai em SwiftShader (rasterização em CPU) a 1920x1080. O RADV da Vega nunca foi construído.

Sintoma relatado, compatível com as duas: **chegou ao sistema, o mouse mexia, mas lentamente demais para
qualquer uso**; a depuração foi abandonada antes de coletar logs.

## Como retomar (ordem que eu seguiria)

1. **Ler os logs que ficaram no SSD**, sem adivinhação: plugar o SSD no Windows e abrir
   `GBOS/gbos/logs/boot-N/` — `kmsg.log`, `hwdetect.txt`, `hook.log` (procure `hook: software rendering:`),
   `PATCH-STATUS`. A imagem prometia `3 applied, 0 not applied, 2 skipped (native SHA-NI)`.
2. **Tirar o USB do caminho do boot**: instalar no Kingston SH103S3240G (disco 0). A máquina já tem, desde
   a cirurgia de disco de 2026-11-15, uma partição `GBOS_EFI` de 512 MB e **47,5 GB livres** no fim desse
   disco. Instalação exige `INSTALL_DISK=sda` + `GBOS_INSTALL_MODE=dualboot` no `gbos.cfg` e o serial digitado
   — o instalador **nunca** oferece SATA sozinho quando há NVMe, e o default dele é `nvme0n1`, o disco do
   Windows. Ver `docs/DEVSAN-TEST-PROTOCOL.md` §0.
3. **Construir o RADV** para `1002:1638` (`tools/radv-android/build.sh`) e reimagem com `GPU_VULKAN=radv`.
4. Enquanto o RADV não existe: `RESOLUTION=1280x720` no `gbos.cfg` reduz os pixels que o SwiftShader paga.

## O que deixei no disco (não versionado)

- `dist/gbOS86-20261115.img` (6,3 GB) + `.sha256` — a imagem que bootou; `stage/` (4,3 GB) é o intermediário.
- `backup-ventoy/Windows11_Client_x64_pt-br_26300_9457.iso` (8,3 GB) — o ISO que estava no SSD antes de
  ele ser usado como stick, salvo e conferido.
- O próprio SSD (`CT240BX5`, 240 GB) está com a imagem gravada.

Todos os itens acima estão no `.gitignore`; nenhum segredo, nenhuma chave.

## O que o fork mudou em relação ao upstream

Commit a commit no `git log`: gate de SHA-NI quando a CPU tem nativo, detecção de ISA por fabricante,
correções de build para host Windows/WSL sem docker, assemble nativo da imagem, e cinco documentos
(`DEVSAN-HARDWARE`, `DEVSAN-PORT`, `DEVSAN-TEST-PROTOCOL`, `DEVSAN-BOOT-REPORT-01`, este).
Nenhuma dessas mudanças foi validada em hardware além do boot descrito acima.
