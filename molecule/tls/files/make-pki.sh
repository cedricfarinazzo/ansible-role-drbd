#!/usr/bin/env bash
# Throwaway test PKI: make-pki.sh DIR NAME...; a CA, another CA, and per NAME a key and a certificate (SAN NAME)
# signed by the CA, one signed by the other CA, one expired; plus a stray key that matches no certificate.
set -euo pipefail
d=$1; shift
mkdir -p "$d"; cd "$d"
ca() {
  openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256 -out "$1.key" 2> /dev/null
  openssl req -x509 -new -key "$1.key" -subj "/CN=$2" -days 30 -out "$1.pem" \
    -addext basicConstraints=critical,CA:TRUE -addext keyUsage=critical,keyCertSign,cRLSign
}
# sign CA NAME OUT [x509 date options...]
sign() {
  local c=$1 n=$2 o=$3; shift 3
  openssl req -new -key "$n.key" -subj "/CN=$n" -out "$o.csr"
  printf 'subjectAltName=DNS:%s\nextendedKeyUsage=serverAuth,clientAuth\nbasicConstraints=CA:FALSE\n' "$n" > "$o.ext"
  openssl x509 -req -in "$o.csr" -CA "$c.pem" -CAkey "$c.key" -extfile "$o.ext" -out "$o.pem" "$@" 2> /dev/null
  rm -f "$o.csr" "$o.ext"
}
[ -f ca.pem ] || ca ca "Example Test CA"
[ -f other-ca.pem ] || ca other-ca "Example Other CA"
[ -f stray.key ] || openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256 -out stray.key 2> /dev/null
for n in "$@"; do
  [ -f "$n.key" ] || openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256 -out "$n.key" 2> /dev/null
  sign ca "$n" "$n" -days 30
  sign other-ca "$n" "$n-other-ca" -days 30
  sign ca "$n" "$n-expired" -not_before 20200101000000Z -not_after 20200201000000Z
done
chmod 0600 ./*.key
