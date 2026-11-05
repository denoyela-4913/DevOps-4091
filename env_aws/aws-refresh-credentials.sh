unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN AWS_CREDENTIAL_EXPIRATION
aws login   # si "aws sts (env propre)" est en échec
eval "$(aws configure export-credentials --format env)"
