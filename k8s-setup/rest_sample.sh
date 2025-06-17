#!/usr/bin/env bash
#
# Copyright IBM Corp All Rights Reserved
#
# SPDX-License-Identifier: Apache-2.0
#

# This magical awk script led to 30 hours of debugging a "TLS handshake error"
# moral: do not edit / alter the number of '\' in the following transform:
function one_line_pem {
    echo "`awk 'NF {sub(/\\n/, ""); printf "%s\\\\\\\n",$0;}' $1`"
}

function json_ccp {
  local ORG=$1
  local PP=$(one_line_pem $2)
  local CP=$(one_line_pem $3)
  local NS=$4
  sed -e "s/\${ORG}/$ORG/" \
      -e "s#\${PEERPEM}#$PP#" \
      -e "s#\${CAPEM}#$CP#" \
      -e "s#\${ORG1_NS}#$NS#" \
      -e "s#\${ORG2_NS}#$NS#" \
      k8s-setup/config/ccp-template.json
}

function construct_rest_sample_configmap() {
  local ns=$ORG1_NS
  push_fn "Constructing fabric-rest-sample connection profiles"

  ENROLLMENT_DIR=${TEMP_DIR}/enrollments
  CHANNEL_MSP_DIR=${TEMP_DIR}/channel-msp
  CONFIG_DIR=${TEMP_DIR}/fabric-rest-sample-config

  mkdir -p $CONFIG_DIR

  # Org1 configuration
  local peer_pem=$CHANNEL_MSP_DIR/peerOrganizations/org1/msp/tlscacerts/tlsca-signcert.pem
  local ca_pem=$CHANNEL_MSP_DIR/peerOrganizations/org1/msp/cacerts/ca-signcert.pem
  echo "$(json_ccp 1 $peer_pem $ca_pem $ORG1_NS)" > $CONFIG_DIR/HLF_CONNECTION_PROFILE_ORG1
  cp $ENROLLMENT_DIR/org1/users/org1admin/msp/signcerts/cert.pem $CONFIG_DIR/HLF_CERTIFICATE_ORG1
  cp $ENROLLMENT_DIR/org1/users/org1admin/msp/keystore/key.pem $CONFIG_DIR/HLF_PRIVATE_KEY_ORG1

  # Org2 configuration
  peer_pem=$CHANNEL_MSP_DIR/peerOrganizations/org2/msp/tlscacerts/tlsca-signcert.pem
  ca_pem=$CHANNEL_MSP_DIR/peerOrganizations/org2/msp/cacerts/ca-signcert.pem
  echo "$(json_ccp 2 $peer_pem $ca_pem $ORG2_NS)" > $CONFIG_DIR/HLF_CONNECTION_PROFILE_ORG2
  cp $ENROLLMENT_DIR/org2/users/org2admin/msp/signcerts/cert.pem $CONFIG_DIR/HLF_CERTIFICATE_ORG2
  cp $ENROLLMENT_DIR/org2/users/org2admin/msp/keystore/key.pem $CONFIG_DIR/HLF_PRIVATE_KEY_ORG2

  # Create ConfigMap for Org1
  kubectl -n $ORG1_NS delete configmap fabric-rest-sample-config-org1 || true
  kubectl -n $ORG1_NS create configmap fabric-rest-sample-config-org1 \
    --from-file=HLF_CONNECTION_PROFILE_ORG1=$CONFIG_DIR/HLF_CONNECTION_PROFILE_ORG1 \
    --from-file=HLF_CERTIFICATE_ORG1=$CONFIG_DIR/HLF_CERTIFICATE_ORG1 \
    --from-file=HLF_PRIVATE_KEY_ORG1=$CONFIG_DIR/HLF_PRIVATE_KEY_ORG1

  # Create ConfigMap for Org2
  kubectl -n $ORG2_NS delete configmap fabric-rest-sample-config-org2 || true
  kubectl -n $ORG2_NS create configmap fabric-rest-sample-config-org2 \
    --from-file=HLF_CONNECTION_PROFILE_ORG2=$CONFIG_DIR/HLF_CONNECTION_PROFILE_ORG2 \
    --from-file=HLF_CERTIFICATE_ORG2=$CONFIG_DIR/HLF_CERTIFICATE_ORG2 \
    --from-file=HLF_PRIVATE_KEY_ORG2=$CONFIG_DIR/HLF_PRIVATE_KEY_ORG2

  pop_fn
}

function rollout_rest_sample() {
  local ns=$1
  local yaml_file=$2
  push_fn "Starting fabric-rest-sample for $ns"

  kubectl -n $ns apply -f $yaml_file
  kubectl -n $ns rollout status deploy/fabric-rest-sample-${ns,,}

  pop_fn
}

function launch_rest_sample() {
  construct_rest_sample_configmap

  # Launch for Org1
  rollout_rest_sample $ORG1_NS kube/fabric-rest-sample-org1.yaml

  # Launch for Org2
  rollout_rest_sample $ORG2_NS kube/fabric-rest-sample-org2.yaml

  log ""
  log "The fabric-rest-sample has started for Org1 and Org2."
  log "See https://github.com/hyperledger/fabric-samples/tree/main/asset-transfer-basic/rest-api-typescript for additional usage details."
  log "To access the endpoints:"
  log ""
  log "For Org1:"
  log "export SAMPLE_APIKEY=97834158-3224-4CE7-95F9-A148C886653E"
  log "curl -s --header \"X-Api-Key: \${SAMPLE_APIKEY}\" http://<NODE_IP>:30001/api/assets"
  log ""
  log "For Org2:"
  log "export SAMPLE_APIKEY=BC42E734-062D-4AEE-A591-5973CB763430"
  log "curl -s --header \"X-Api-Key: \${SAMPLE_APIKEY}\" http://<NODE_IP>:30002/api/assets"
  log ""
}