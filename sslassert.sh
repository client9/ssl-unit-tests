#!/bin/sh

#
# defaults
#
if [ "$URLPATH" = "" ]; then
    export URLPATH=/
fi

if [[ "$HOSTPORT" != *:* ]]; then
    export HOSTPORT="${HOSTPORT}:443"
fi

export SSLFACTS=""
export SSLASSERT_EXIT=0


function sslfact_add {
    FACT=$1
    if [ "$SSLASSERT_DEBUG" != "" ]; then
        echo $FACT 2>&1
    fi
    SSLFACTS="$SSLFACTS\n$FACT"
}

function sslfact_certificate_length {
    bits=`echo $URLPATH | openssl s_client -connect $HOSTPORT 2> /dev/null | grep -E 'Server public key is ([0-9]+) bit' |  awk '{ print $5 }'`
    sslfact_add "certificate-length: $bits"
}

function sslfact_self_signed_certificates_in_chain {
    echo $URLPATH | openssl s_client -connect $HOSTPORT 2> /dev/null | grep -i -q 'self signed certificate in certificate chain'
    if [ "$?" -eq "0" ]; then
        ACTUAL="on"
    else
        ACTUAL="off"
    fi
    sslfact_add "self-signed-certificates-in-chain: $ACTUAL"
}

function sslfact_certificate_chain_length {
    numcerts=`echo $URLPATH | openssl s_client -showcerts -connect $HOSTPORT 2> /dev/null | grep 'BEGIN CERTIFICATE' | wc -l | tr -d ' '`
    sslfact_add "certificate-chain-length: $numcerts"
}

function sslfact_secure_renegotiation {
    echo $URLPATH | openssl s_client -connect $HOSTPORT 2> /dev/null | grep -i -q 'Secure Renegotiation IS supported'
    # grep $? is
    #     0     One or more lines were selected.
    #     1     No lines were selected.
    #     >1    An error occurred.

    if [ "$?" -eq "0" ]; then
        ACTUAL="on"
    else
        ACTUAL="off"
    fi
    sslfact_add "secure-renegotiation: ${ACTUAL}"
}


function sslfact_compression {
    EXPECTED=$1

    echo $URLPATH | openssl s_client -connect $HOSTPORT 2> /dev/null | grep -i -q 'Compression: NONE'

    # grep $? is
    #     0     One or more lines were selected.
    #     1     No lines were selected.
    #     >1    An error occurred.

    if [ "$?" -eq "0" ]; then
        ACTUAL="off"
    else
        ACTUAL="on"
    fi
    sslfact_add "compression: ${ACTUAL}"
}

function sslfact_protocol_tls_v12 {
    cipher=`echo $URLPATH | openssl s_client -tls1_2 -connect $HOSTPORT 2> /dev/null | awk -F ': *' '/Cipher.*:/ { print $2 }'`
    if [ "$cipher" = "0000" ]; then
        ACTUAL="off"
    else
        ACTUAL="on"
    fi
    sslfact_add "protocol-tls-v12: ${ACTUAL}"
    sslfact_add "protocol-tls-v12-default: ${cipher}"
}

function sslfact_protocol_tls_v11 {
    cipher=`echo $URLPATH | openssl s_client -tls1_1 -connect $HOSTPORT 2> /dev/null | awk -F ': *' '/Cipher.*:/ { print $2 }'`
    if [ "$cipher" = "0000" ]; then
        ACTUAL="off"
    else
        ACTUAL="on"
    fi
    sslfact_add "protocol-tls-v11: ${ACTUAL}"
    sslfact_add "protocol-tls-v11-default: ${cipher}"
}

function sslfact_protocol_tls_v10 {
    cipher=`echo $URLPATH | openssl s_client -tls1 -connect $HOSTPORT 2> /dev/null | awk -F ': *' '/Cipher.*:/ { print $2 }'`
    if [ "$cipher" = "0000" ]; then
        ACTUAL="off"
    else
        ACTUAL="on"
    fi
    sslfact_add "protocol-tls-v10: ${ACTUAL}"
    sslfact_add "protocol-tls-v10-default: ${cipher}"
}

function sslfact_protocol_ssl_v3 {
    cipher=`echo $URLPATH | openssl s_client -ssl3 -connect $HOSTPORT 2> /dev/null | awk -F ': *' '/Cipher.*:/ { print $2 }'`
    if [ "$cipher" = "0000" ]; then
        ACTUAL="off"
    else
        ACTUAL="on"
    fi
    sslfact_add "protocol-ssl-v3: ${ACTUAL}"
    sslfact_add "protocol-ssl-v3-default: ${cipher}"
}

function sslfact_protocol_ssl_v2 {
    cipher=`echo $URLPATH | openssl s_client -ssl2 -connect $HOSTPORT 2> /dev/null | awk -F ': *' '/Cipher.*:/ { print $2 }'`
    if [ "$cipher" -eq "0000" ]; then
        ACTUAL="off"
    else
        ACTUAL="on"
    fi
    sslfact_add "protocol-ssl-v2: ${ACTUAL}"
    sslfact_add "protocol-ssl-v2-default: ${cipher}"
}

function sslfact_cipher_suites {
    OPENSSLSUITES=`openssl ciphers -V | awk '{ print $3 }'`
    for CIPHER in $OPENSSLSUITES; do
        echo $URLPATH | openssl s_client -cipher ${CIPHER} -connect $HOSTPORT 2> /dev/null > /dev/null
        if [ "$?" -eq "0" ]; then
            sslfact_add "cipher-suite-${CIPHER}: on"
        else
            sslfact_add "cipher-suite-${CIPHER}: off"
        fi
    done
}

function has_cipher_suites {
    FNAME=$1
    COUNT=$2
    if [ "$COUNT" == "0" ]; then
       ACTUAL="off"
    else
       ACTUAL="on"
    fi
    sslfact_add "${FNAME}: ${ACTUAL}"
}

function sslfact_crypto_weak {
    COUNT=`echo $SSLFACTS | grep -i 'cipher-suite-.*: on' | grep -c -E 'EXP-|-DES-CBC-'`
    has_cipher_suites "crypto-weak" $COUNT
}

function sslfact_crypto_idea {
    COUNT=`echo $SSLFACTS | grep -i 'cipher-suite.*: on' | grep -c IDEA-`
    has_cipher_suites "crypto-idea" $COUNT
}

function sslfact_crypto_rc4 {
    COUNT=`echo $SSLFACTS | grep -i 'cipher-suite-.*: on' | grep -c RC4`
    has_cipher_suites "crypto-rc4" $COUNT
}

function sslfact_crypto_tripledes {
    COUNT=`echo $SSLFACTS | grep -i 'cipher-suite-.*: on' | grep -c -E '3DES|CBC3'`
    has_cipher_suites "crypto-3des" $COUNT
}

function sslfact_crypto_camellia {
    COUNT=`echo $SSLFACTS | grep -i 'cipher-suite-.*: on' | grep -c CAMELLIA`
    has_cipher_suites "crypto-camellia" $COUNT
}

function sslfact_crypto_md5 {
    COUNT=`echo $SSLFACTS | grep -i 'cipher-suite-.*: on' | grep -c MD5`
    has_cipher_suites 'crypto-md5' $COUNT
}

function sslfact_crypto_sha160 {
    COUNT=`echo $SSLFACTS | grep -i 'cipher-suite-.*: on' | grep SHA | grep -c -v -E 'SHA256|SHA384|SHA512'`
    has_cipher_suites 'crypto-sha160' $COUNT
}

function sslfact_crypto_forward_secrecy {
    # ignoring insecure DES based suites
    COUNT=`echo $SSLFACTS | grep -i 'cipher-suite-.*: on' | grep -E 'ECDHE|EDH-' | grep -c -v 'DES-CBC-'`
    has_cipher_suites 'crypto-forward-secrecy' $COUNT
}

function sslfact_beast_attack {
    BEAST=0
    echo $SSLFACTS | grep -i -q -E 'protocol-tls-v10-default:.*(RC4|0000)'
    if [ "$?" -eq 0 ]; then
        let BEAST+=1
    fi
    echo $SSLFACTS | grep -i -q -E 'protocol-ssl-v3-default:.*(RC4|0000)'
    if [ "$?" -eq 0 ]; then
        let BEAST+=1
    fi
    if [ "$BEAST" -eq 2 ]; then
        ACTUAL="off"
    else
        ACTUAL="on"
    fi
    sslfact_add "beast-attack: ${ACTUAL}"
}

function recommendation_ssllabs {
    sslassert 'secure-renegotiation = on'
    sslassert 'protocol-SSL-v2      = off'
    sslassert 'protocol-TLS-V10     = on'
    sslassert 'crypto-weak          = off'
    sslassert 'compression          = off'
    sslassert 'beast-attack         = off'
    sslassert 'certificate-length -ge 1024'
}


function sslassert {
    read -r KEY OP EXPECTED <<< $1

    # take only first value
    ACTUAL=`echo $SSLFACTS | grep -i "$KEY" | head -1 | awk -F : '{ print \$2 }' | tr -d ' '`

    if [ "$?" -ne 0 ]; then
        echo "ERR : ${KEY}: not found!!"
        return 2
    fi

    if [ "$ACTUAL" "$OP" "$EXPECTED" ]; then
        echo "PASS: ${KEY}: ${ACTUAL} ${OP} ${EXPECTED}"
        return 0
    fi

    echo "FAIL: ${KEY}: ${ACTUAL} ${OP} ${EXPECTED}"
    SSLASSERT_EXIT=1
    return 1
}

function sslassert_init {
    sslfact_cipher_suites
    sslfact_crypto_weak
    sslfact_crypto_md5
    sslfact_crypto_rc4
    sslfact_crypto_idea
    sslfact_crypto_camellia
    sslfact_crypto_tripledes
    sslfact_crypto_forward_secrecy
    sslfact_crypto_sha160
    sslfact_certificate_length
    sslfact_self_signed_certificates_in_chain
    sslfact_certificate_chain_length
    sslfact_secure_renegotiation
    sslfact_compression
    sslfact_protocol_tls_v12
    sslfact_protocol_tls_v11
    sslfact_protocol_tls_v10
    sslfact_protocol_ssl_v2
    sslfact_protocol_ssl_v3
    sslfact_beast_attack
}
sslassert_init
