# Checklist de campo

Para imprimir e levar junto com o pendrive.

## Preparar o pendrive (uma vez)

- [ ] Pendrive de 32 GB+ , conteúdo já salvo em outro lugar
- [ ] Dispositivo conferido em `lsblk -o NAME,SIZE,TRAN,MODEL`
- [ ] `sudo ./scripts/preparar-pendrive.sh -d /dev/sdX`
- [ ] `sudo ./scripts/verificar-pendrive.sh -d /dev/sdX` sem falhas
- [ ] Boot testado em uma máquina UEFI **e** em uma BIOS/legado

## Máquina modelo (antes de capturar)

- [ ] Sistema, drivers genéricos e programas padrão instalados
- [ ] Atualizações aplicadas e reinício concluído
- [ ] BitLocker / LUKS desativados
- [ ] Windows: `powercfg /h off`
- [ ] Windows: espaço livre zerado (`sdelete64 -z C:`)
- [ ] Linux: `machine-id` zerado, chaves SSH de host removidas, caches limpos
- [ ] Contas de teste, tokens, senhas salvas e históricos removidos
- [ ] Windows: `sysprep /generalize /oobe /shutdown` executado — não religar

## Capturar

- [ ] Boot pelo pendrive → `Clonezilla live` → `Enter_shell`
- [ ] `sudo mount -L IMAGENS /home/partimag`
- [ ] `sudo /home/partimag/scripts/clonar-maquina.sh`
- [ ] Nome da imagem anotado: ______________________
- [ ] Log em `logs/` sem erros
- [ ] `NOTAS.txt` criado dentro da pasta da imagem
- [ ] Restauração testada em **uma** máquina antes do lote
- [ ] Cópia da imagem guardada fora do pendrive

## Restaurar (por máquina)

- [ ] Dados do usuário já salvos, se a máquina não for nova
- [ ] Modo de boot no setup igual ao da máquina modelo (UEFI × Legacy)
- [ ] Controlador em AHCI
- [ ] `sudo /home/partimag/scripts/restaurar-maquina.sh -i <imagem> -d /dev/sdX`
- [ ] Máquina inicia e chega à área de trabalho
- [ ] Nome da máquina / hostname definido
- [ ] Licença ativada (Windows) e ingresso no domínio, se houver
- [ ] Drivers específicos do modelo instalados
- [ ] Rede, impressora e antivírus funcionando
- [ ] Patrimônio, modelo, imagem usada e data registrados

## Encerramento

- [ ] Pendrive desmontado com segurança (`sync` antes de remover)
- [ ] Imagens antigas e inúteis apagadas de `imagens/`
- [ ] Logs revisados
