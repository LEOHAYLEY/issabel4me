1. Execute no Issabel
```bash
curl -fsSL \
  https://raw.githubusercontent.com/LEOHAYLEY/issabel4me/main/update_themes.sh \
  -o /usr/local/sbin/update_themes.sh
chmod 750 /usr/local/sbin/update_themes.sh
 ```


2. Primeiro, faça uma simulação:
```bash
/usr/local/sbin/update_themes.sh --dry-run
 ```


4. Se os caminhos e arquivos estiverem corretos, execute a atualização:
```bash
/usr/local/sbin/update_themes.sh
 ```

Ao terminar, pressione Ctrl + F5 no navegador para atualizar o CSS e validar o login, o logo e as cores do menu.
