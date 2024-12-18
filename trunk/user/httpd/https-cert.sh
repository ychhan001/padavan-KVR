#!/bin/sh

if [ ! -x /usr/bin/openssl ] && [ ! -x /opt/bin/openssl ]; then
  echo "无法找到 'openssl' 可执行文件！" >&2
  echo "请从 Entware 安装 'openssl-util' 软件包。" >&2
  exit 1
fi

umask 0022

DH_GEN=0
DH_BITS=1024
RSA_BITS=1024
CA_DAYS=3653
CERT_DAYS=365
DSTDIR=/etc/storage/https
SSL_EXT_FILE=/etc/ssl/openssl_ext2.cnf
ECPARAM=ecparam.pem

func_help() {
  local BOLD="echo -ne \\033[1m"
  local NORM="echo -ne \\033[0m"
  echo "为 HTTP SSL 服务器创建自签名证书。" >&2
  echo >&2
  echo "`$BOLD`使用方法:`$NORM`" >&2
  echo "    $0 -n `$BOLD`common_name`$NORM` [ -b `$BOLD`rsa_bits/ec_name`$NORM` ] [ -d `$BOLD`days_valid`$NORM` ] [ -p {DH} ]" >&2
  echo >&2
  echo "`$BOLD`例如:`$NORM`" >&2
  echo "    $0 -n myname.no-ip.com -b 2048 -d 30" >&2
  echo >&2
  echo "`$BOLD`默认值:`$NORM`"
  echo "    rsa_bits=`$BOLD`$RSA_BITS`$NORM`, days_valid=`$BOLD`$CERT_DAYS`$NORM`" >&2
  echo >&2
  exit 1
}

echo_done() {
  echo -e " *\033[60G [ 完成 ]"
}

echo_process() {
  echo -ne " + $@\r"
}

is_cn_valid() {
  # RFC 1034 (https://tools.ietf.org/html/rfc1034#section-3.5)
  if [ -n "`echo $1 | sed 's/^[a-zA-Z][0-9a-zA-z\.-]\{1,253\}[0-9a-zA-Z]$//'`" ] ; then
    return 1
  fi
  for i in  `echo $1 | sed 's/\./ /g'` ; do
    if [ `echo -n $i | wc -c` -gt 63 ] ; then
      return 1
    fi
  done
  return 0
}

create_cert() {
  [ -z "$CN" ] && func_help
  if ! is_cn_valid $CN ; then
     echo >&2
     echo "警告: $CN 不是一个有效的主机名" >&2
     echo >&2
  fi

  [ -d $DSTDIR ] || mkdir -m 755 -p $DSTDIR
  if ! cd $DSTDIR ; then
    echo "错误: 无法切换到 $DSTDIR" >&2
    return 1
  fi

  # Check if -sha256 is supported
  local DGST_ALG
  DGST_ALG="-sha1"
  openssl list -1 --digest-commands 2>&1 | grep -q 'sha256' && DGST_ALG="-sha256"

  rm -f $SSL_EXT_FILE
  cat > $SSL_EXT_FILE << EOF
[ server ]
basicConstraints=CA:FALSE
subjectKeyIdentifier=hash
authorityKeyIdentifier=keyid,issuer:always
extendedKeyUsage=serverAuth,clientAuth
keyUsage=critical,digitalSignature,keyEncipherment
subjectAltName=DNS:${CN},DNS:my.router
EOF

  local C_PARAM="rsa:${RSA_BITS}"
  if echo $RSA_BITS | grep -q '^[bpsw]'; then
    openssl ecparam -name "$RSA_BITS" -out "$ECPARAM"
    C_PARAM="ec:$ECPARAM"
  fi

  echo_process "创建 CA (Certificate Authority)证书颁发机构"
  openssl req -nodes -x509 -days $CA_DAYS -newkey $C_PARAM \
            -outform PEM -out ca.crt -keyout ca.key \
            $DGST_ALG -subj "/CN=HTTPS CA" &>/dev/null
  chmod 600 ca.key
  echo_done

  echo_process "创建证书请求"
  openssl req -nodes -days $CERT_DAYS -newkey $C_PARAM \
            -outform PEM -out server.csr -keyout server.key \
            $DGST_ALG -subj "/CN=$CN" &>/dev/null
  chmod 600 server.key
  echo_done

  echo_process "签名请求"
  openssl x509 -req -in server.csr -CA ca.crt -CAkey ca.key -CAcreateserial \
               -clrext -out server.crt $DGST_ALG -extfile $SSL_EXT_FILE \
               -days $CERT_DAYS -extensions server &>/dev/null
  rm -f server.csr
  echo_done

  if [ $DH_GEN -eq 1 ] ; then
    echo_process "创建 DH 参数（可能需要很长时间，请耐心等待）"
    openssl dhparam -out dh1024.pem $DH_BITS &>/dev/null
    echo_done
  fi

  [[ -f "$ECPARAM" ]] && rm -f "$DSTDIR/$ECPARAM"
  rm -f ca.srl
}

while [ $# -gt 0 ] ; do
  case "$1" in
    -n) CN="$2" ; shift 2 ;;
    -b) RSA_BITS=$2 ; shift 2 ;;
    -d) CERT_DAYS=$2 ; shift 2 ;;
    -p) DH_GEN=1 ; shift 1 ;;
     *) func_help ; ;;
  esac
done

create_cert

exit $?
