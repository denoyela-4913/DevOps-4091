#!/usr/bin/env bash
# Diagnostic de l'environnement AWS / Terraform.
# Usage : ./diag-aws.sh   (à lancer dans le shell où vous utilisez terraform)
# Aucun secret n'est affiché.

cd "$(dirname "$0")" || exit 1

ok()   { printf '  \033[32m✔\033[0m %-26s %s\n' "$1" "$2"; }
ko()   { printf '  \033[31m✘\033[0m %-26s %s\n' "$1" "$2"; FAIL=1; }
warn() { printf '  \033[33m!\033[0m %-26s %s\n' "$1" "$2"; }
hdr()  { printf '\n\033[1m%s\033[0m\n' "$1"; }
FAIL=0

hdr "Outils"
if command -v aws >/dev/null; then ok "aws cli" "$(aws --version 2>&1 | cut -d' ' -f1)"; else ko "aws cli" "introuvable"; fi
if command -v terraform >/dev/null; then ok "terraform" "$(terraform version | head -1)"; else ko "terraform" "introuvable"; fi

hdr "Configuration AWS"
CFG=~/.aws/config
if [ -f "$CFG" ]; then
  grep -q login_session "$CFG" && ok "méthode de connexion" "aws login (login_session)" \
    || ok "méthode de connexion" "autre (profil/clés/SSO)"
  REGION_CFG=$(awk -F'= *' '/^region/{print $2; exit}' "$CFG")
  ok "région du profil" "${REGION_CFG:-non définie}"
else
  ko "~/.aws/config" "absent"
fi

hdr "Variables d'environnement (ce shell)"
for v in AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN; do
  if [ -n "${!v}" ]; then ok "$v" "définie"; else warn "$v" "absente"; fi
done
for v in AWS_PROFILE AWS_DEFAULT_PROFILE AWS_REGION AWS_DEFAULT_REGION AWS_SHARED_CREDENTIALS_FILE AWS_CONFIG_FILE; do
  [ -n "${!v}" ] && warn "$v" "= ${!v}  (peut prendre le dessus)"
done
if [ -n "$AWS_CREDENTIAL_EXPIRATION" ]; then
  exp=$(date -d "$AWS_CREDENTIAL_EXPIRATION" +%s 2>/dev/null)
  now=$(date +%s)
  if [ -n "$exp" ] && [ "$exp" -gt "$now" ]; then ok "expiration des variables" "dans $(( (exp-now)/60 )) min"
  else
    ko "expiration des variables" "EXPIRÉES ($AWS_CREDENTIAL_EXPIRATION)"
    STALE=1
  fi
fi
###[ -z "$AWS_ACCESS_KEY_ID" ] && warn "terraform (provider 4.x)" "ne verra rien : faites l'eval ci-dessous"
[ -z "$AWS_ACCESS_KEY_ID" ] && warn "terraform (provider 4.x)" "ne verra rien : faites l'eval ci-dessous" && ABSENT=1

hdr "Session AWS"
# Environnement sans variables AWS_* : teste la session aws login elle-même
CLEAN="env -u AWS_ACCESS_KEY_ID -u AWS_SECRET_ACCESS_KEY -u AWS_SESSION_TOKEN -u AWS_CREDENTIAL_EXPIRATION"
skew=$(( $(date +%s) - $(date -d "$(curl -sI --max-time 5 https://sts.amazonaws.com | awk -F': ' 'tolower($1)=="date"{print $2}')" +%s 2>/dev/null || echo "$(date +%s)") ))
if [ "${skew#-}" -gt 60 ]; then ko "horloge" "décalage de ${skew}s avec AWS -> wsl --shutdown / hwclock -s"; else ok "horloge" "synchronisée avec AWS"; fi
if id=$(aws sts get-caller-identity --query Arn --output text 2>&1); then
  ok "aws sts (shell actuel)" "${id##*:}"
else
  ko "aws sts (shell actuel)" "$(echo "$id" | tail -1 | cut -c1-70)"
fi
if id=$($CLEAN aws sts get-caller-identity --query Arn --output text 2>&1); then
  ok "aws sts (env propre)" "session aws login valide"
else
  ko "aws sts (env propre)" "session aws login expirée -> aws login"
fi
if out=$($CLEAN aws configure export-credentials --format env 2>&1) && echo "$out" | grep -q AWS_ACCESS_KEY_ID; then
  ok "export-credentials" "OK (eval possible)"
  CREDS="$out"
else
  ko "export-credentials" "échec : $(echo "$out" | tail -1 | cut -c1-70)"
fi
if [ -n "$STALE" ]; then
  printf '\n  \033[33m→ Variables AWS_* périmées dans ce shell. Elles masquent votre session.\033[0m\n'
  printf '    unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN AWS_CREDENTIAL_EXPIRATION\n'
  printf '    aws login   # si "aws sts (env propre)" est en échec\n'
  printf '    eval "$(aws configure export-credentials --format env)"\n'
fi
if [ -n "$ABSENT" ]; then
  printf '\n  \033[33m→ Variables AWS_* absentes dans ce shell. Elles doivent etre ajoutees a votre session.\033[0m\n'
  printf '    eval "$(aws configure export-credentials --format env)"\n'
fi

hdr "Terraform"
LOCKV=$(awk '/hashicorp\/aws/{f=1} f&&/version/{gsub(/[" ]/,"",$3); print $3; exit}' .terraform.lock.hcl 2>/dev/null)
[ -n "$LOCKV" ] && ok "provider aws (lock)" "$LOCKV" || warn "provider aws (lock)" "terraform init non fait ?"
if [ -n "$LOCKV" ] && [ "${LOCKV%%.*}" -lt 6 ] && grep -q login_session "$CFG" 2>/dev/null; then
  warn "provider vs aws login" "provider ancien : ne lit pas login_session -> utiliser l'eval"
fi
REGION_TF=$(awk -F'"' '/^[[:space:]]*region[[:space:]]*=/{print $2; exit}' main.tf)
ok "région (main.tf)" "${REGION_TF:-?}"
[ -n "$REGION_CFG" ] && [ -n "$REGION_TF" ] && [ "$REGION_CFG" != "$REGION_TF" ] \
  && warn "région profil != main.tf" "$REGION_CFG vs $REGION_TF (main.tf prime)"
terraform validate -no-color >/dev/null 2>&1 && ok "terraform validate" "OK" || ko "terraform validate" "échec (lancer terraform validate)"

hdr "Droits EC2 dans la région du main.tf (dry-run, rien n'est créé)"
if [ -n "$REGION_TF" ] && [ -n "$CREDS" ]; then
  r=$(eval "$CREDS"; aws ec2 create-security-group --group-name diag-dryrun --description diag --dry-run --region "$REGION_TF" 2>&1)
  if echo "$r" | grep -q DryRunOperation; then ok "CreateSecurityGroup" "autorisé"
  elif echo "$r" | grep -q 'explicit deny'; then ko "CreateSecurityGroup" "REFUSÉ par une SCP dans $REGION_TF"
  else ko "CreateSecurityGroup" "$(echo "$r" | tail -1 | cut -c1-80)"; fi
else
  warn "dry-run" "ignoré (pas de credentials exportables)"
fi

hdr "Verdict"
if [ "$FAIL" = 0 ]; then
  printf '  \033[32mTout est bon.\033[0m Si terraform échoue, lancez : eval "$(aws configure export-credentials --format env)"\n\n'
else
  printf '  \033[31mProblèmes détectés (✘ ci-dessus).\033[0m Corrigez de haut en bas, puis relancez ce script.\n\n'
fi
exit $FAIL
