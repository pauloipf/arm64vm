# Virtualization ARM64

🇺🇸 [Read in English](README.md)

Gerenciador mínimo de máquinas virtuais Linux (ARM64) para Macs com Apple Silicon, usando o `Virtualization.framework` nativo do macOS, sem VirtualBox, UTM ou Parallels. Começou com o **Kali Linux**, mas roda outras distros ARM64. Cada VM fica na sua própria pasta, e tudo é um único arquivo Swift.

## Requisitos

- Mac com **Apple Silicon** (M1 ou mais recente)
- **macOS 14 (Sonoma)** ou mais recente
- Xcode Command Line Tools: `xcode-select --install`
- Uma ISO **ARM64/aarch64** da distro que você quer instalar (veja [Outras distros](#outras-distros))

## Instalação

```sh
git clone https://github.com/pauloipf/arm64vm.git
cd arm64vm
./build.sh
```

O `build.sh` compila o `main.swift` e assina o executável com o `entitlements.plist` (permissão `com.apple.security.virtualization`). Sem essa assinatura, o macOS não deixa a VM iniciar. Rode o script de novo depois de qualquer alteração no código.

## Estrutura

```
arm64vm/
├── main.swift           código-fonte
├── build.sh             compila e assina
├── entitlements.plist   permissão com.apple.security.virtualization
├── arm64vm              executável (gerado pelo build.sh, ignorado pelo git)
└── vms/                 suas VMs: local, ignorada pelo git, NUNCA publique
    └── <nome>/          uma pasta por VM (ex.: kali, ubuntu)
        ├── disk.img       disco virtual (esparso: ocupa só o espaço usado)
        ├── efi_variables  variáveis UEFI (criado automaticamente)
        ├── config.json    núcleos e RAM da VM (criado automaticamente)
        ├── *.iso          instalador (usado só com --install)
        └── compartilhado/ pasta compartilhada com o sistema convidado
```

## Configuração de cada VM

- **CPU:** padrão de 2 a 4 núcleos (o total do Mac menos 2), ajustável com `--cpus`
- **Memória:** padrão de 4 GB, ajustável com `--mem`, com memory balloon
- **Boot:** UEFI
- **Disco:** `disk.img` via virtio. Com `--install`, a ISO entra como pendrive USB
- **Rede:** NAT (a VM acessa a internet pelo Mac)
- **Vídeo:** virtio, 1920×1080, com ajuste automático ao tamanho da janela
- **Entrada:** teclado USB e mouse USB por coordenadas de tela
- **Áudio:** somente saída
- **Pasta compartilhada:** virtiofs com a tag `compartilhado`

Os arquivos são procurados na pasta onde está o executável, então o `arm64vm` pode ser chamado de qualquer diretório.

## Uso

### Passo a passo: uma VM Ubuntu

Rode todos os comandos de dentro da pasta do projeto (`cd arm64vm`), nesta ordem.

1. **Baixe a ISO.** Pegue a versão **ARM64** do Ubuntu (Desktop ou Server) em [ubuntu.com/download](https://ubuntu.com/download). Depois compare o checksum com o publicado no site:
   ```sh
   shasum -a 256 ~/Downloads/ubuntu-*-arm64.iso
   ```
2. **Crie a pasta da VM e mova a ISO para ela.** O nome da pasta é o nome da VM:
   ```sh
   mkdir -p vms/ubuntu
   mv ~/Downloads/ubuntu-*-arm64.iso vms/ubuntu/
   ```
3. **Crie o disco e inicie o instalador:**
   ```sh
   ./arm64vm --vm ubuntu --new 64g --install
   ```
   O `--new` cria um `disk.img` esparso do tamanho pedido (`64g`, `128g`...) e **se recusa** a sobrescrever um disco existente. Para já escolher núcleos e RAM, acrescente: `--cpus 4 --mem 6g`.
4. **Instale o Ubuntu** na janela que abrir. No particionamento, escolha o **disco virtio** (o tamanho que você definiu). Não escolha o pendrive USB, que é a ISO.
5. **Reinicie.** Quando o instalador pedir para reiniciar, a janela fecha sozinha (ou feche você mesmo).
6. **Inicie o sistema instalado.** Daqui em diante, sempre sem `--install`:
   ```sh
   ./arm64vm --vm ubuntu
   ```
7. **Opcional: ajuste núcleos e RAM** com a VM desligada. Os valores ficam salvos para os próximos boots:
   ```sh
   ./arm64vm --vm ubuntu --cpus 6 --mem 8g
   ```
8. **Confira suas VMs:**
   ```sh
   ./arm64vm --list
   ```
9. **Opcional: libere espaço** apagando a ISO, que não é mais necessária:
   ```sh
   rm vms/ubuntu/ubuntu-*-arm64.iso
   ```

Os mesmos passos valem para qualquer distro de [Outras distros](#outras-distros). Só mudam a ISO e o nome da VM.

### Referência de comandos

| Comando | O que faz |
|---|---|
| `./arm64vm --vm <nome>` | Inicia a VM pelo disco |
| `./arm64vm --vm <nome> --new 64g --install` | Cria a VM com um disco novo e abre o instalador |
| `./arm64vm --vm <nome> --install` | Abre o instalador com a única `.iso` de `vms/<nome>/` |
| `./arm64vm --vm <nome> --install outra.iso` | Abre o instalador com uma ISO específica |
| `./arm64vm --vm <nome> --cpus 6 --mem 8g` | Muda núcleos e RAM (fica salvo) e inicia a VM |
| `./arm64vm --list` | Lista as VMs com núcleos, RAM e disco |
| `./arm64vm --help` | Mostra a ajuda |

Sem `--vm`, o app usa a VM existente se houver apenas uma. Com mais de uma, ele pede que você indique qual.

### Núcleos e RAM

Núcleos e RAM podem ser alterados a qualquer momento, com a VM desligada, sem afetar o sistema instalado.

- Os valores ficam em `vms/<nome>/config.json`. Cada VM tem os seus, e dá para editar o arquivo direto.
- Formatos aceitos em `--mem`: `8g` ou `8gb`, em GB inteiros.
- Limites: de 1 núcleo até o total do Mac, e de 1 GB até a RAM do Mac menos 2 GB, que ficam reservados para o macOS. O app recusa valores fora disso.
- O **tamanho do disco** não muda por aqui. Ele é definido no `--new`.

### Reinstalar uma VM do zero

Com a VM desligada, apague a pasta dela e crie de novo. **Isso apaga a instalação**:

```sh
mv vms/kali/kali-linux-*.iso ~/Downloads/   # guarde a ISO, se for reutilizar
rm -r vms/kali
mkdir -p vms/kali && mv ~/Downloads/kali-linux-*.iso vms/kali/
./arm64vm --vm kali --new 64g --install
```

O `efi_variables` é recriado junto. Isso é necessário, porque ele guarda a ordem de boot da instalação anterior.

### Desligar

- Fechar a janela ou apertar **Cmd+Q** envia um pedido de desligamento ao sistema convidado, como apertar o botão de energia. O app fecha sozinho quando ele termina de desligar.
- Se o sistema não responder, feche de novo. Aparece um aviso com a opção **Forçar desligamento**, que equivale a tirar da tomada e pode perder dados não salvos.
- Desligar ou reiniciar por dentro da VM (`sudo poweroff`, `sudo reboot`) também fecha o app.

### Teclado

Clique dentro da janela para que ela receba o teclado. Enquanto a janela estiver em foco, atalhos do sistema como Cmd+Tab vão para a VM.

## Outras distros

Funcionam as distros que tenham **ISO ARM64 (aarch64)** com **boot UEFI**, por exemplo:

| Distro | Qual ISO baixar |
|---|---|
| Kali Linux | Installer para **ARM64** |
| Ubuntu | Ubuntu Desktop ou Server para **ARM64** |
| Debian | `debian-*-arm64-netinst.iso` |
| Fedora | Workstation ou Server para **aarch64** |
| openSUSE | Tumbleweed ou Leap para **aarch64** |
| Rocky / AlmaLinux | DVD ou minimal para **aarch64** |
| Arch Linux ARM | Instalação manual, mais trabalhosa |

ISOs **x86_64 / amd64** (os downloads "padrão" da maioria dos sites) **não funcionam**, porque o `Virtualization.framework` não emula outra arquitetura.

Todas essas distros já reconhecem disco virtio, rede, vídeo, teclado e mouse.

## Pasta compartilhada

A pasta `vms/<nome>/compartilhado` de cada VM fica disponível dentro dela com a tag `compartilhado`. Ela tem **leitura e escrita**: a VM pode alterar e apagar o que estiver lá, então não coloque arquivos sensíveis nela.

Para montar uma vez:

```sh
sudo mkdir -p /mnt/compartilhado
sudo mount -t virtiofs compartilhado /mnt/compartilhado
```

Para montar automaticamente em todo boot, adicione esta linha ao `/etc/fstab` da VM:

```
compartilhado  /mnt/compartilhado  virtiofs  rw,nofail  0  0
```

## Solução de problemas

| Problema | O que fazer |
|---|---|
| Teclado não funciona | Clique dentro da janela da VM |
| VM volta para o instalador | Inicie sem `--install` |
| "VM não encontrada" | Confira o nome com `./arm64vm --list`, ou crie a VM com `--new` |
| "disk.img já existe" | O `--new` não sobrescreve discos. Veja [Reinstalar uma VM do zero](#reinstalar-uma-vm-do-zero) |
| "Nenhuma .iso encontrada" | Coloque a ISO dentro de `vms/<nome>/` |
| "Mais de uma .iso na pasta" | Indique a ISO: `./arm64vm --vm <nome> --install <arquivo.iso>`, ou remova as antigas |
| Instalador não inicia ou tela preta | Confira se a ISO é **ARM64/aarch64**, e não amd64 |
| "Núcleos inválidos" ou "Memória inválida" | Use valores dentro dos limites mostrados na mensagem |
| "Indique a VM com --vm" | Há mais de uma VM: passe `--vm <nome>` (veja `./arm64vm --list`) |
| "Erro ao iniciar a VM" ou erro de permissão | Rode `./build.sh` de novo para reassinar o executável |

## Segurança

- **Nunca publique nem compartilhe a pasta `vms/`.** Um `disk.img` instalado contém o sistema inteiro: hashes de senha, histórico, chaves SSH etc. O `.gitignore` já exclui `vms/`, discos e ISOs.
- Para reportar vulnerabilidades, veja [SECURITY.md](SECURITY.md).

## Aviso legal

Este projeto não tem afiliação com a Apple, a OffSec (Kali Linux) nem com nenhuma das distribuições citadas. As marcas pertencem aos seus respectivos donos. Nenhuma ISO é distribuída aqui: baixe sempre dos sites oficiais. Ferramentas de segurança, como as do Kali, devem ser usadas apenas em sistemas que você tem autorização para testar.

## Licença

Distribuído sob a [Apache License 2.0](LICENSE). Veja também o arquivo [NOTICE](NOTICE).
