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
      tf plan [-c TERRAFORM_CONFIGURATION] [-t RESOURCE] [-- TERRAFORM_OPTIONS ]
      tf apply [-c TERRAFORM_CONFIGURATION] [-a] [-t RESOURCE] [-- TERRAFORM_OPTIONS ]
      tf show [-c TERRAFORM_CONFIGURATION] [-- TERRAFORM_OPTIONS ]
      tf destroy [-c TERRAFORM_CONFIGURATION] [-- TERRAFORM_OPTIONS ]
      tf clean

DESCRIPTION
      get a specific revision of the lib git repository, change the backend to fit the environment parameter, and then plan or apply terraform

      init
           check if a tmp folder exists, eventually download terraform scripts, and run terraform init

      plan
           generates a terraform plan for the specified configuration

      apply
           creates resources planified with plan command

      show
           issue the terraform show command for the specified configuration

      destroy
           issue the terraform destroy command for the specified configuration

      clean
           clean .terraform and .tmp folder

      -c | --configuration TERRAFORM_CONFIGURATION
            The name of the configuration to apply. It must be within the configuration directory in modules.git.
            Mandatory
            Can be set with CONFIGURATION environment variable

      -r | --revision GIT_REVISION
            the git revision to extract from modules.git
            Can be set with GIT_REVISION environment variable

      -l | --lib-url LIB_URL
            git modules repository url
            Defaults to git@git.corp.cloudwatt.com:pocwatt/terraform/lib.git
            Can be set with LIB_URL environment variable

      -e | --environment ENVIRONMENT
            The environment (i.e DNS domain) we are targetting
            Defaults to the current git repo name
            Can be set with ENVIRONMENT environment variable

EXAMPLE
      tf apply -c base -r ref/head/master -m git@git.corp.cloudwatt.com:pocwatt/terraform/mylib.git -e client1
      CONFIGURATION=base tf init
"
  }

function _tf_init () {
  if ! [[ -d "${TMP_DIR}/configurations/${CONFIGURATION}" ]]; then
    _tf_clean
    mkdir "${TMP_DIR}" || true
    # now we clone lib.git repository
    git clone "${LIB_URL}" "${TMP_DIR}"
  fi
  (
    cd "${TMP_DIR}"
    git fetch origin
    git reset --hard "${GIT_REVISION}"
  )
  # add any tf and tfvars files present here to override the downloaded configuration
  cp ./*.tf ./*.tfvars "${TMP_DIR}/configurations/${CONFIGURATION}" &>/dev/null || true

  # environment replacement in every *tf* files
  sed -i "s/#ENVIRONMENT#/${ENVIRONMENT}/g" "${TMP_DIR}"/configurations/"${CONFIGURATION}"/*.tf*
  # terraform init
  (
    cd "${TMP_DIR}/configurations/${CONFIGURATION}"
    terraform init -upgrade=true
  )
}

function _tf_clean () {
  rm -rf "${TMP_DIR}" &>/dev/null || true
}

function _tf_plan () {
  _tf_init
  (
    cd "${TMP_DIR}/configurations/${CONFIGURATION}"
    # shellcheck disable=2086
    terraform plan ${TERRAFORM_OPTIONS} -out="../../tf.out"
  )
}

function _tf_apply () {
  if ! [[ -f "../tf.out" ]]; then _tf_plan; fi
  (
    cd "${TMP_DIR}/configurations/${CONFIGURATION}"
    # shellcheck disable=2086
    terraform apply ${TERRAFORM_OPTIONS} "../../tf.out"
  )
}

function _tf_show () {
  (
    cd "${TMP_DIR}/configurations/${CONFIGURATION}"
    # shellcheck disable=2086
    terraform show ${TERRAFORM_OPTIONS}
  )
}

function _tf_destroy () {
  (
    cd "${TMP_DIR}/configurations/${CONFIGURATION}"
    # shellcheck disable=2086
    terraform destroy ${TERRAFORM_OPTIONS}
  )
}

function _tf_parsing () {
  # trying to source our environments variables
  # shellcheck disable=1091
  source "tffile" &>/dev/null || true
  # some default variables
  GIT_REVISION="${GIT_REVISION:-refs/heads/master}"
  LIB_URL="${LIB_URL:-git@git.corp.cloudwatt.com:pocwatt/terraform/lib.git}"
  ACTION=$1;
  ENV=$(basename "$(git remote get-url origin 2>/dev/null)")
  ENVIRONMENT="${ENVIRONMENT:-${ENV%.*}}"
  TMP_DIR="./.tmp"

  case ${ACTION} in
    apply | plan | init | clean | show | destroy)
    ;;
    * )
    _tf_help;
    exit 1;;
  esac

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
        -l | --lib-url )
          shift;
          LIB_URL=$1;;
        -e | --environment )
          shift;
          ENVIRONMENT=$1;;
        -- )
          shift;
          TERRAFORM_OPTIONS="$*";
          break;;
        *)
          _tf_help;exit 1;;
      esac
      shift;
  done

  # mandatory parameters check
  case ${ACTION} in
    init | plan | apply | destroy )
    if [[ -z "${CONFIGURATION}" ]]; then
      echo "Missing configuration option"
      _tf_help; exit 1;
    fi
    if [[ -z "${ENVIRONMENT}" ]]; then
      echo "Missing environment option"
      _tf_help; exit 1;
    fi
    ;;
  esac

  # let's display every parameter
  echo "ACTION: ${ACTION}"
  echo "CONFIGURATION: ${CONFIGURATION}"
  echo "GIT_REVISION: ${GIT_REVISION}"
  echo "LIB_URL: ${LIB_URL}"
  echo "ENVIRONMENT: ${ENVIRONMENT}"
  echo "TMP_DIR: ${TMP_DIR}"
  echo "TERRAFORM_OPTIONS: ${TERRAFORM_OPTIONS}"
  terraform -v
}

_tf_parsing "$@"
"_tf_${ACTION}"
