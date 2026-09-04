import Config

# Runtime configuration lives in env vars read by Shepherd.Bao:
#   BAO_ADDR    (required; RFD 2195: https://weftspun-bao.<tailnet>.ts.net:8200)
#   BAO_TOKEN   (required; never ~/.bao-token, which is shared on a shared-$HOME box)
#   BAO_CACERT  (default /etc/ssl/cert.pem)
#
# Nothing else is configured statically. A Burrito binary embeds this
# file at build time, so anything host-specific must remain env-driven.
