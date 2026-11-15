# Relatório de boot 01 — DEVSAN (2026-11-15)

Primeiro boot real do gbOS86 nesta máquina, com o SSD Crucial BX500 240 GB por USB.

## O que foi feito

1. Imagem `gbOS86-20261115.img` (6.712.983.552 bytes, sha256 `86d137ed…`, GPT p1 ESP 256 MiB + p2 `GBOS` 6 GiB).
2. Gravada crua em `\\.\PhysicalDrive2` (`CT240BX5`, gaveta USB-SATA) a partir do Windows, com
   `FILE_FLAG_WRITE_THROUGH` + `FlushFileBuffers`, blocos de 16 MB. 6.402 MB em 21,7 s.
3. Verificação por releitura crua do dispositivo: sha256 idêntico ao da imagem (`SHA_OK`).
4. Boot por UEFI a partir do SSD, escolha do modo live.

## O que aconteceu (relato do usuário)

> "Entrou no sistema, eu selecionei a opção para realmente ser live CD. O mouse mexia, mas muito lentamente
> e desisti de debugar."

> "Até botou, ficou muito lento, muito lento mesmo. Ficou quase inutilizável tudo. Então não deu pra usar,
> nem mexer, nem ele dizer como que foi."

- O menu apareceu e a escolha foi **live** (não o instalador). O sistema **bootou até o Android** — não foi
  tela preta, não foi kernel panic, não foi reboot.
- O ponteiro do mouse **respondia**, ou seja: entrada, compositor e display estavam funcionando. Faltava
  velocidade — latência alta o suficiente para inviabilizar qualquer operação e a leitura de diagnóstico na tela.
- A depuração foi abandonada antes de coletar `logcat`/`kmsg` na mão. **Os logs do boot continuam no SSD**
  (`GBOS/gbos/logs/boot-N/`), gravados pelo stage0 automaticamente; nada foi lido ainda porque o SSD não
  estava plugado no Windows depois do teste.

**Status: encerrado sem diagnóstico fechado.** O projeto foi arquivado em 2026-11-15
(`docs/DEVSAN-ARCHIVE.md`).

## O que o código de boot faz (fonte: `usb/stage0_init.sh`, o mesmo embutido no kernel)

O modo live monta o Android a partir de um único arquivo grande na partição FAT32 do stick:

```sh
losetup -r /dev/loop7 $G/super.img                       # super.img de 3,5 GB
mount -t erofs -o ro /dev/loop$i $t                      # /system, /vendor, /product, ...
```

Ou seja, **todo acesso ao sistema de arquivos raiz é: erofs ← loop device ← arquivo em FAT32 ← gaveta USB-SATA**.
Não há cache de bloco útil para leituras aleatórias espalhadas, e a gaveta USB é justamente o elo que já
provou resetar sob carga (`disk` 153 + `UASPStor` 129).

`/data` e `/metadata` vão para tmpfs (RAM) no modo live, então escrita não é o problema — **leitura é**.

## Hipóteses, em ordem de peso

1. **I/O do `/system` sobre USB/FAT32/loop.** Explica lentidão generalizada, travadas ao abrir qualquer app e
   demora para chegar ao desktop. É estrutural do modo live, não um defeito desta máquina.
2. **Sem aceleração de GPU: SwiftShader.** `GPU_VULKAN=auto` só usa RADV se `gbos/patched/vulkan.radv.so`
   existir, e ele não foi construído (`tools/radv-android/build.sh`, fase 4). Sem isso o boot cai em
   SwiftShader: rasterização 100 % em CPU, a 1920x1080 (`RESOLUTION=` vazio = nativo). Combina com "não deu
   nem pra mexer".
3. **Gaveta USB-SATA instável.** Já derrubou escritas de 257 MB e 2.560 MB antes; no boot, cada reset de UAS
   vira uma pausa de segundos no meio de uma leitura de página do erofs.
4. Menos provável: `TRUSTY_VM` (é `0` por default), `A11Y` (sem `gbos/a11y/`, não ativa), `REQUIRE_AVX`
   (a CPU tem AVX2, então não para).

## O que ainda falta para fechar o diagnóstico

Os logs **estão no SSD**, escritos pelo próprio stage0 em `GBOS/gbos/logs/boot-N/`. Como o SSD não está
plugado agora, ainda não foram lidos. O que importa em cada um:

| arquivo | o que prova |
|---|---|
| `kmsg.log` | tempo entre marcos do boot, erros de USB (`usb … reset`), I/O travado (`task hung`) |
| `hwdetect.txt` | o que a detecção achou: CPU, iGPU `1002:1638`, se carregou `amdgpu` |
| `hook.log` / linha `hook:` | qual renderizador entrou: `software rendering: … RADV` ou `SwiftShader` |
| `PATCH-STATUS` | `3 applied, 0 not applied, 2 skipped (native SHA-NI)` — confirma o gate SHA-NI |
| `boot.log` / `init.log` | em que ponto do Android init ele parou ou demorou |

## Próximos passos, em ordem de custo/benefício

1. **Ler os logs** (só plugar o SSD) — sem isso, tudo acima é hipótese.
2. **Tirar o USB do caminho do boot**: instalar no Kingston SATA (disco 0), que já tem 47,5 GB livres e a
   partição `GBOS_EFI` de 512 MB preparadas. `INSTALL_DISK=sda` + `GBOS_INSTALL_MODE=dualboot` no `gbos.cfg`,
   serial digitado. O instalador nunca oferece SATA sozinho quando existe NVMe — tem que ser explícito, e
   **nunca** deixar o default (`nvme0n1`, o disco do Windows).
3. **Construir o RADV** (`tools/radv-android/build.sh`) para a Vega `1002:1638` e reimagem com
   `GPU_VULKAN=radv`. É o que troca "renderizado na CPU" por "renderizado na iGPU".
4. Opcional para o teste seguinte: `RESOLUTION=1280x720` no `gbos.cfg` — menos pixels para o SwiftShader
   enquanto o RADV não existe.

## Ficha da máquina (para o relatório)

Ryzen 7 5700G (8c/16t, AVX2 nativo) · Radeon Vega iGPU `1002:1638` (display) · RX 550X `1002:699F` ociosa ·
B450M · 31,3 GB RAM · disco 0 Kingston SH103S3240G 240 GB SATA · disco 1 NE-256 NVMe 240 GB (Windows) ·
alvo do teste: Crucial BX500 240 GB em gaveta USB-SATA.
