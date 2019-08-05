#!/usr/bin/env bash
#

# Usage
# chmod +x ./create-certs.sh
# ./create-certs.sh --api-token --api-host https://g.codefresh.io 

#---
fatal() {
   echo "ERROR: $1"
   exit 1
}

exit_trap () {
  local lc="$BASH_COMMAND" rc=$?
  if [ $rc != 0 ]; then
    if [[ -n "$SLEEP_ON_ERROR" ]]; then
      echo -e "\nSLEEP_ON_ERROR is set - Sleeping to fix error"
      sleep $SLEEP_ON_ERROR
    fi
  fi
}
trap exit_trap EXIT


# Args
while [[ $1 =~ ^(-(h|t|c|n|r)|--(api-host|api-token|cluster-name|namespace|helm-release|server-cert-cn|server-cert-extra-sans)) ]]
do
  key=$1
  value=$2

  case $key in
    -h|--api-host)
        API_HOST="$value"
        shift
      ;;
    -t|--api-token)
        API_TOKEN="$value"
        shift
      ;;
    -c|--cluster-name)
        CLUSTER_NAME="$value"
        shift
      ;;
    -n|--namespace)
        NAMESPACE="$value"
        shift
      ;;
    -r|--helm-release)
        HELM_RELEASE="$value"
        shift
      ;;
    --server-cert-cn)
        SERVER_CERT_CN="$value"
        shift
      ;;
    --server-cert-extra-sans)
        SERVER_CERT_EXTRA_SANS="$value"
        shift
      ;;
  esac
  shift # past argument or value
done

echo $NAMESPACE
echo $CLUSTER_NAME

API_VALIDATE_PATH=${SIGN_VALIDATE_PATH:-"api/custom_clusters/validate"}
API_SIGN_PATH=${API_SIGN_PATH:-"api/custom_clusters/signServerCerts"}
HELM_RELEASE=${HELM_RELEASE:-"codefresh-runner"}
# API_HOST=${API_HOST}
# API_TOKEN=${API_TOKEN}
# CLUSTER_NAME=${CLUSTER_NAME}
# NAMESPACE=${NAMESPACE}
SERVER_CERT_CN="${SERVER_CERT_CN}"
SERVER_CERT_EXTRA_SANS="${SERVER_CERT_EXTRA_SANS}"

[[ -z "$API_TOKEN" ]] && fatal "Missing API Token"
[[ -z "$API_HOST" ]] && fatal "Missing API Host"
[[ -z "$CLUSTER_NAME" ]] && fatal "Missing Kubernetes Cluster Name"
[[ -z "$NAMESPACE" ]] && fatal "Missing Kubernetes Namespace"

NAMESPACE=${NAMESPACE:-default}

DIR=$(dirname $0)
TMPDIR=./tmp/codefresh
TMP_VALIDATE_RESPONSE_FILE=$TMPDIR/validate-response
TMP_VALIDATE_HEADERS_FILE=$TMPDIR/validate-headers.txt

TMP_CERTS_FILE_ZIP=$TMPDIR/cf-certs.zip
TMP_CERTS_HEADERS_FILE=$TMPDIR/cf-certs-response-headers.txt
CERTS_DIR=./tmp/codefresh/certs-tmp
SRV_TLS_KEY=${CERTS_DIR}/server-key.pem
SRV_TLS_CSR=${CERTS_DIR}/server-cert.csr
SRV_TLS_CERT=${CERTS_DIR}/server-cert.pem
CF_SRV_TLS_CERT=${CERTS_DIR}/cf-server-cert.pem
CF_SRV_TLS_CA_CERT=${CERTS_DIR}/cf-ca.pem
mkdir -p $TMPDIR $CERTS_DIR

K8S_CERT_SECRET_NAME=codefresh-certs-server
# docker info 2>/dev/null | awk 'BEGIN{FS=": "}/Storage Driver:/{print $2}'

echo -e "\n------------------\nValidating and get values from API HOST  ... "
echo "{\"clusterName\": \"$CLUSTER_NAME\", \"namespace\": \"$NAMESPACE\"}" > ${TMPDIR}/validate_req.json

VALIDATE_STATUS=$(curl -sSL -d @${TMPDIR}/validate_req.json  -H "Content-Type: application/json" -H "authorization: ${API_TOKEN}" \
      -o ${TMP_VALIDATE_RESPONSE_FILE} -D ${TMP_VALIDATE_HEADERS_FILE} -w '%{http_code}' ${API_HOST}/${API_VALIDATE_PATH} )
echo "Validate Node request completed with HTTP_STATUS_CODE=$VALIDATE_STATUS"
if [[ $VALIDATE_STATUS != 200 ]]; then
   echo "ERROR: Node Validation failed"
   if [[ -f ${TMP_VALIDATE_RESPONSE_FILE} ]]; then
     mv ${TMP_VALIDATE_RESPONSE_FILE} ${TMP_VALIDATE_RESPONSE_FILE}.error
     cat ${TMP_VALIDATE_RESPONSE_FILE}.error
   fi
   exit 1
fi

echo "Validate response: "
cat ${TMP_VALIDATE_RESPONSE_FILE}
echo

export CF_REGISTRY_DOMAIN=$(cat ${TMP_VALIDATE_RESPONSE_FILE} | jq -rM .registry.domain)
export CF_REGISTRY_PROTOCOL=$(cat ${TMP_VALIDATE_RESPONSE_FILE} | jq -rM .registry.protocol)
export CF_REGISTRY_USER=$(cat ${TMP_VALIDATE_RESPONSE_FILE} | jq -rM .registry.user)

echo "CF_REGISTRY_DOMAIN=$CF_REGISTRY_DOMAIN"
echo "CF_REGISTRY_PROTOCOL=$CF_REGISTRY_PROTOCOL"
echo "CF_REGISTRY_USER=$CF_REGISTRY_USER"

[[ -z "$CF_REGISTRY_DOMAIN" ]] && fatal "Validation failed - cannot get CF_REGISTRY_DOMAIN"

API_REGISTER_PATH=${API_REGISTER_PATH:-"api/custom_clusters/register"}

# Register Runner
echo -e "\n------------------\nRegistering Runtime ... "
REGISTER_DATA=\
"{\"clusterName\": \"${CLUSTER_NAME}\",
\"namespace\": \"${NAMESPACE}\",
\"storageClassName\": \"dind-local-volumes-venona-${NAMESPACE}\",
\"agent\": true
}"

echo "${REGISTER_DATA}" > ${TMPDIR}/register_data.json

rm -f ${TMPDIR}/register.out ${TMPDIR}/register_response_headers.out
REGISTER_STATUS=$(curl -sSL -d @${TMPDIR}/register_data.json -H "Content-Type: application/json" -H "authorization: ${API_TOKEN}" \
    -o ${TMPDIR}/register.out -D ${TMPDIR}/register_response_headers.out -w '%{http_code}' ${API_HOST}/${API_REGISTER_PATH} )

echo "Registration request completed with HTTP_STATUS_CODE=$REGISTER_STATUS"
if [[ $REGISTER_STATUS == 200 ]]; then
 echo -e "Cluster Namespace has been successfully registered with Codefresh\n------"
else
 echo "ERROR: Failed to register cluster node with Codefresh"
 [[ -f ${TMPDIR}/register.out ]] && cat ${TMPDIR}/register.out
 echo -e "\n----\n"
 exit 1
fi

echo -e "\n------------------\nGenerating server tls certificates ... "

SERVER_CERT_CN=${SERVER_CERT_CN:-"docker.codefresh.io"}
###

  openssl genrsa -out $SRV_TLS_KEY 4096 || fatal "Failed to generate openssl key "
  openssl req -subj "/CN=${SERVER_CERT_CN}" -new -key $SRV_TLS_KEY -out $SRV_TLS_CSR  || fatal "Failed to generate openssl csr "
  GENERATE_CERTS=true
  
  CSR=$(cat ./tmp/codefresh/certs-tmp/server-cert.csr)

  SERVER_CERT_SANS="IP:127.0.0.1,DNS:dind,DNS:*.dind.${NAMESPACE},DNS:*.dind.${NAMESPACE}.svc,DNS:*.cf-cd.com,DNS:*.codefresh.io"
  if [[ -n "${SERVER_CERT_EXTRA_SANS}" ]]; then
    SERVER_CERT_SANS=${SERVER_CERT_SANS},${SERVER_CERT_EXTRA_SANS}
  fi
  echo ${SERVER_CERT_SANS}
  echo ${CSR}
  jq -n '{reqSubjectAltName: $SERVER_CERT_SANS, csr: $CSR}' --arg CSR "${CSR}" --arg SERVER_CERT_SANS "${SERVER_CERT_SANS}" > ${TMPDIR}/sign_req.json
  #echo "{\"reqSubjectAltName\": \"${SERVER_CERT_SANS}\", \"csr\": \"${CSR}\" }" > ${TMPDIR}/sign_req.json

  rm -fv ${TMP_CERTS_HEADERS_FILE} ${TMP_CERTS_FILE_ZIP}
  SIGN_STATUS=$(curl -sSL -d @${TMPDIR}/sign_req.json -H "Content-Type: application/json" -H "authorization: ${API_TOKEN}" -H "Expect: " \
        -o ${TMP_CERTS_FILE_ZIP} -D ${TMP_CERTS_HEADERS_FILE} -w '%{http_code}' ${API_HOST}/${API_SIGN_PATH} )

  echo "Sign request completed with HTTP_STATUS_CODE=$SIGN_STATUS"
  if [[ $SIGN_STATUS != 200 ]]; then
     echo "ERROR: Cannot sign certificates"
     if [[ -f ${TMP_CERTS_FILE_ZIP} ]]; then
       mv ${TMP_CERTS_FILE_ZIP} ${TMP_CERTS_FILE_ZIP}.error
       cat ${TMP_CERTS_FILE_ZIP}.error
     fi
     exit 1
  fi
  unzip -o -d ${CERTS_DIR}/  ${TMP_CERTS_FILE_ZIP} || fatal "Failed to unzip certificates to ${CERTS_DIR} "
  cp -v ${CF_SRV_TLS_CERT} $SRV_TLS_CERT || fatal "received ${TMP_CERTS_FILE_ZIP} does not contains cf-server-cert.pem"

echo "BASE64 ca: "
base64 -i ./tmp/codefresh/certs-tmp/cf-ca.pem

echo "BASE64 cert: "
base64 -i ./tmp/codefresh/certs-tmp/cf-server-cert.pem

echo "BASE64 key: "
base64 -i ./tmp/codefresh/certs-tmp/server-key.pem

# Generating Runner Token

echo "Generating Runner Token"

TOKEN_NAME=$(echo codefresh-runner-$(date '+%Y%m%d%H%M%S'))

jq -n '{name: $TOKEN_NAME}' --arg TOKEN_NAME "${TOKEN_NAME}"  > ${TMPDIR}/token-data.json

echo "Agent Token: "

AGENT_TOKEN=$(curl -X POST \
  "${API_HOST}/api/auth/key?subjectType=runtime-environment&subjectReference=${CLUSTER_NAME}/${NAMESPACE}" \
  -H "Authorization: Bearer ${API_TOKEN}" \
  -H "Content-Type: application/json" \
  -d @${TMPDIR}/token-data.json)

echo "Agent Token: "

echo ${AGENT_TOKEN}

echo "Update values.yaml with values above or use --set for the values"

echo "Example Helm Command: helm upgrade --install --namespace ${NAMESPACE} ${HELM_RELEASE} ./codefresh-runner"