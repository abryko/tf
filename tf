#!/usr/bin/env bash
set -e
set -o pipefail

# help function
function _tf_help () {
echo "
NAME
      clone caascad terraform configuration and its modules and apply it

SYNPOSIS
      tf init [-c TERRAFORM_CONFIGURATION] [-r GIT_REVISION] [-l LIB_URL] [-e ENVIRONMENT]
      tf plan [-c TERRAFORM_CONFIGURATION] [-t RESOURCE]
      tf apply [-c TERRAFORM_CONFIGURATION] [-a] [-t RESOURCE]
      tf clean

DESCRIPTION
      get a specific revision of the lib git repository, change the backend to fit the environment parameter, and then plan or apply terraform

      init
           check if a tmp folder exists, eventually download terraform scripts, and run terraform init
      
      plan
           generates a terraform plan for the specified configuration

      apply
           creates resources planified with plan command         

      clean
           clean .terraform and .tmp folder

      -c | --configuration TERRAFORM_CONFIGURATION
            The name of the configuration to apply. It must be within the configuration directory in modules.git.
            Mandatory
            Can be set with CONFIGURATION environment variable

      -r | --revision GIT_REVISION
            the git revision to extract from modules.git
            Can be set with GIT_REVISION environment variable

      -l | --lib_url LIB_URL
            git modules repository url
            Defaults to git@git.corp.cloudwatt.com:pocwatt/terraform/lib.git
            Can be set with LIB_URL environment variable

      -e | --environment ENVIRONMENT
            The environment (i.e DNS domain) we are targetting
            Defaults to the current git repo name
            Can be set with ENVIRONMENT environment variable
      
      -t | --target RESOURCE
            The target terraform resource to update
            Can be set with TARGET environment variable

      -a | --auto-approve
            Skip interactive approval of plan before applying
            Can be set with AUTO_APROVE environment variable

EXAMPLE
      tf apply -c base -r ref/head/master -m git@git.corp.cloudwatt.com:pocwatt/terraform/mylib.git -e client1
      CONFIGURATION=base tf init
"
  }

function _tf_init () {
  if ! [ -d "${TMP_DIR}/configurations/${CONFIGURATION}" ]; then 
    _tf_clean
    mkdir "${TMP_DIR}" || true
    # now we clone lib.git repository
    git clone "${LIB_URL}" "${TMP_DIR}"
  fi
  (
    cd "${TMP_DIR}";
    git reset --hard "${GIT_REVISION}"
  )
  # environment replacement in backend
  sed -i "s/#ENVIRONMENT#/${ENVIRONMENT}/g" "${TMP_DIR}/configurations/${CONFIGURATION}/backend.tf"
  # add any tf and tfvars files present here to override the downloaded configuration
  cp ./*.tf ./*.tfvars "${TMP_DIR}/configurations/${CONFIGURATION}" &>/dev/null || true
  # terraform init
  terraform init -upgrade=true "${TMP_DIR}/configurations/${CONFIGURATION}"
  }

function _tf_clean () {
  rm -rf "${TMP_DIR}" .terraform &>/dev/null || true
  }

function _tf_plan () {
  _tf_init
  terraform plan ${TARGET_RESOURCE} -out="${TMP_DIR}/tf.out" "${TMP_DIR}/configurations/${CONFIGURATION}"
  }

function _tf_apply () {
  if ! [ -f "${TMP_DIR}/tf.out" ]; then _tf_plan ; fi
  terraform apply ${TARGET_RESOURCE} ${AUTO_APPROVE} "${TMP_DIR}/tf.out"
  }

function _tf_parsing () {
  # trying to source our environments variables
  source "tffile" &>/dev/null
  # some default variables
  GIT_REVISION="${GIT_REVISION:-refs/heads/master}"
  LIB_URL="${LIB_URL:-git@git.corp.cloudwatt.com:pocwatt/terraform/lib.git}"
  ACTION=$1;
  ENV=$(basename "$(git remote get-url origin)")
  ENVIRONMENT="${ENVIRONMENT:-${ENV%.*}}"
  TMP_DIR="./.tmp"
  
  if [ "${ACTION}" != "apply" ] && [ "${ACTION}" != "plan" ] && [ "${ACTION}" != "init" ] && [ "${ACTION}" != "clean" ]; then _tf_help; exit 1; fi
  shift;
  # parameters parsing
  while [[ $# -gt 1 ]]
    do
      par=$1 ;
      case $par in
        -c | --configuration )
          shift;
          CONFIGURATION=$1;;
        -r | --revision )
          shift;
          GIT_REVISION=$1;;
        -l | --lib_url )
          shift;
          LIB_URL=$1;;
        -e | --environment )
          shift;
          ENVIRONMENT=$1;;
        -t | --target )
          shift;
          TARGET=$1;;
        -a | --auto-approve )
          AUTO_APPROVE="-auto-approve";;
        *)
          _tf_help;exit 1;;
      esac
      shift;
  done
  TARGET_RESOURCE=""
  if  [ -n "${TARGET}" ]; then TARGET_RESOURCE="-target=${TARGET}"; fi

  # mandatory parameters check
  if { [ "${ACTION}" == "init" ] || [ "${ACTION}" == "plan" ] || [ "${ACTION}" == "apply" ]; } && [ -z "${CONFIGURATION}" ]; then 
    echo "Missing configuration option"
    _tf_help; exit 1;
  fi
  
  # let's display every parameter
  echo "ACTION: ${ACTION}"
  echo "CONFIGURATION: ${CONFIGURATION}"
  echo "GIT_REVISION: ${GIT_REVISION}"
  echo "LIB_URL: ${LIB_URL}"
  echo "ENVIRONMENT: ${ENVIRONMENT}"
  echo "TMP_DIR: ${TMP_DIR}"
  echo "TARGET: ${TARGET}"
}

_tf_parsing "$@"
"_tf_${ACTION}"
