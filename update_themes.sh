#!/usr/bin/env bash
# Atualiza a identidade visual Solve4Me no Issabel4Me usando o repositório GitHub.
# Atualiza somente login.tpl, _menu.tpl, custom.css e solve4me_login.png.
# Não altera a integração Genesys/OAuth nem outros arquivos do servidor.

set -Eeuo pipefail

REPO_ARCHIVE_URL="https://github.com/LEOHAYLEY/issabel4me/archive/refs/heads/main.tar.gz"
THEME_DIR="/var/www/html/themes/tenant"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="/root/backup-issabel4me-themes-${STAMP}"
WORK_DIR=""

usage() {
  cat <<'USAGE'
Uso:
  sudo bash update_themes.sh [--dry-run] [--help]

Opções:
  --dry-run  Baixa e valida os arquivos, mas não altera o Issabel.
  --help     Exibe esta ajuda.

O script atualiza apenas:
  login.tpl          -> /var/www/html/themes/tenant/_common/login.tpl
  _menu.tpl          -> /var/www/html/themes/tenant/_common/_menu.tpl
  custom.css         -> /var/www/html/themes/tenant/css/custom.css
  solve4me_login.png -> /var/www/html/themes/tenant/images/solve4me_login.png

Antes de substituir arquivos existentes, cria um backup em /root.
USAGE
}

DRY_RUN=0
case "${1:-}" in
  "") ;;
  --dry-run) DRY_RUN=1 ;;
  --help|-h) usage; exit 0 ;;
  *) echo "ERRO: opção desconhecida: $1" >&2; usage >&2; exit 2 ;;
esac

fail() {
  echo "ERRO: $*" >&2
  exit 1
}

cleanup() {
  if [[ -n "${WORK_DIR}" && -d "${WORK_DIR}" ]]; then
    rm -rf -- "${WORK_DIR}"
  fi
}
trap cleanup EXIT

[[ "${EUID}" -eq 0 ]] || fail "execute como root (ex.: sudo bash update_themes.sh)."
command -v tar >/dev/null 2>&1 || fail "comando 'tar' não encontrado."
command -v install >/dev/null 2>&1 || fail "comando 'install' não encontrado."
command -v mktemp >/dev/null 2>&1 || fail "comando 'mktemp' não encontrado."

if command -v curl >/dev/null 2>&1; then
  DOWNLOADER="curl"
elif command -v wget >/dev/null 2>&1; then
  DOWNLOADER="wget"
else
  fail "instale curl ou wget para baixar o repositório."
fi

[[ -d "${THEME_DIR}/_common" ]] || fail "tema não encontrado: ${THEME_DIR}/_common. Confirme se este servidor usa o tema 'tenant'."
[[ -d "${THEME_DIR}/css" ]] || fail "diretório CSS não encontrado: ${THEME_DIR}/css"
[[ -d "${THEME_DIR}/images" ]] || fail "diretório de imagens não encontrado: ${THEME_DIR}/images"
id asterisk >/dev/null 2>&1 || fail "usuário 'asterisk' não existe; nada foi alterado."
getent group asterisk >/dev/null 2>&1 || fail "grupo 'asterisk' não existe; nada foi alterado."

WORK_DIR="$(mktemp -d /tmp/issabel4me-themes.XXXXXX)"
ARCHIVE="${WORK_DIR}/issabel4me-main.tar.gz"
echo "[1/5] Baixando personalização do GitHub..."
if [[ "${DOWNLOADER}" == "curl" ]]; then
  curl --fail --location --silent --show-error --retry 2 --connect-timeout 15 \
    "${REPO_ARCHIVE_URL}" -o "${ARCHIVE}" || fail "não foi possível baixar o repositório. Verifique a conectividade com github.com."
else
  wget -q --tries=3 --timeout=20 -O "${ARCHIVE}" "${REPO_ARCHIVE_URL}" || fail "não foi possível baixar o repositório. Verifique a conectividade com github.com."
fi

mkdir -p "${WORK_DIR}/src"
tar -xzf "${ARCHIVE}" -C "${WORK_DIR}/src" || fail "o arquivo baixado não é um TAR.GZ válido."
SRC_DIR="${WORK_DIR}/src/issabel4me-main"
[[ -d "${SRC_DIR}" ]] || fail "estrutura inesperada no arquivo do GitHub: pasta issabel4me-main não encontrada."

FILES=("login.tpl" "_menu.tpl" "custom.css" "solve4me_login.png")
for name in "${FILES[@]}"; do
  [[ -s "${SRC_DIR}/${name}" ]] || fail "arquivo ausente ou vazio no repositório: ${name}"
done

echo "[2/5] Validando os destinos..."
DESTS=(
  "${THEME_DIR}/_common/login.tpl"
  "${THEME_DIR}/_common/_menu.tpl"
  "${THEME_DIR}/css/custom.css"
  "${THEME_DIR}/images/solve4me_login.png"
)
for dest in "${DESTS[@]}"; do
  [[ -d "$(dirname "${dest}")" ]] || fail "diretório de destino não existe: $(dirname "${dest}")"
done

if [[ "${DRY_RUN}" -eq 1 ]]; then
  echo "[3/5] Modo de simulação: nenhum arquivo será alterado."
  for i in "${!FILES[@]}"; do
    dest="${DESTS[$i]}"
    if [[ -f "${dest}" ]] && cmp -s "${SRC_DIR}/${FILES[$i]}" "${dest}"; then
      echo "  IGUAL: ${dest}"
    else
      echo "  ATUALIZARIA: ${dest}"
    fi
  done
  echo "[4/5] Backup e cópia ignorados no modo --dry-run."
  echo "[5/5] Simulação concluída."
  exit 0
fi

echo "[3/5] Criando backup dos arquivos atuais em ${BACKUP_DIR}..."
mkdir -p "${BACKUP_DIR}"
for i in "${!FILES[@]}"; do
  dest="${DESTS[$i]}"
  rel="${dest#/var/www/html/}"
  if [[ -e "${dest}" || -L "${dest}" ]]; then
    mkdir -p "${BACKUP_DIR}/$(dirname "${rel}")"
    cp -a -- "${dest}" "${BACKUP_DIR}/${rel}"
  else
    echo "  AVISO: ${dest} não existia; não há versão anterior para backup."
  fi
done
printf 'Backup criado em: %s\n' "${BACKUP_DIR}" > "${BACKUP_DIR}/INFO.txt"
printf 'Origem: %s\nData: %s\n' "${REPO_ARCHIVE_URL}" "$(date --iso-8601=seconds)" >> "${BACKUP_DIR}/INFO.txt"

echo "[4/5] Instalando os arquivos..."
UPDATED=()
for i in "${!FILES[@]}"; do
  source_file="${SRC_DIR}/${FILES[$i]}"
  dest="${DESTS[$i]}"
  if [[ -f "${dest}" ]] && cmp -s "${source_file}" "${dest}"; then
    echo "  SEM ALTERAÇÃO: ${dest}"
    continue
  fi
  staged="${dest}.solve4me-new.$$"
  install -o asterisk -g asterisk -m 0644 -- "${source_file}" "${staged}"
  if ! mv -f -- "${staged}" "${dest}"; then
    rm -f -- "${staged}"
    echo "ERRO ao substituir ${dest}. O backup está em ${BACKUP_DIR}." >&2
    exit 1
  fi
  UPDATED+=("${dest}")
  echo "  ATUALIZADO: ${dest}"
done

# Reforça proprietário/permissões nos quatro arquivos esperados.
chown asterisk:asterisk "${DESTS[@]}"
chmod 0644 "${DESTS[@]}"

echo "[5/5] Atualização concluída."
if [[ "${#UPDATED[@]}" -eq 0 ]]; then
  echo "Os quatro arquivos já estavam iguais à versão do GitHub. Nenhum conteúdo precisou ser substituído."
else
  echo "Arquivos alterados: ${#UPDATED[@]}"
fi
echo "Backup: ${BACKUP_DIR}"
echo "Próximo passo: no navegador, pressione Ctrl+F5 e valide login, logo, menu e submenus."
echo "Escopo: somente os quatro arquivos de identidade visual listados; a pasta /var/www/html/genesys não foi alterada."
