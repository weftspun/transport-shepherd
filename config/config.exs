import Config

# Runtime configuration lives in env vars read by Shepherd.Bao:
#   BAO_ADDR    (default https://bao.chibifire.com:8200)
#   BAO_TOKEN   (falls back to ~/.bao-token from a prior `bao login`)
#   BAO_CACERT  (default /etc/ssl/cert.pem)
#
# Nothing else is configured statically. A Burrito binary embeds this
# file at build time, so anything host-specific must remain env-driven.
