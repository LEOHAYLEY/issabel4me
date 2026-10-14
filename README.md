curl -fsSL \
  https://raw.githubusercontent.com/LEOHAYLEY/issabel4me/main/update_themes.sh \
  -o /usr/local/sbin/update_themes.sh

chmod 750 /usr/local/sbin/update_themes.sh



/usr/local/sbin/update_themes.sh --dry-run
