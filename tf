#!/usr/bin/env bash
set -e
set -o pipefail

# help function
function _tf_help () {

cat <<EOF
NAME
      Thin wrapper around terraform to work with Caascad configurations

SYNPOSIS
      tf init [-c CONFIGURATION] [-r GIT_REVISION] [-l LIB_URL] [-e ENVIRONMENT]
      tf plan [-c CONFIGURATION] [-r GIT_REVISION] [-- TERRAFORM_OPTIONS ]
      tf apply [-c CONFIGURATION] [-r GIT_REVISION] [-- TERRAFORM_OPTIONS ]
      tf show [-c CONFIGURATION] [-- TERRAFORM_OPTIONS ]
      tf destroy [-c CONFIGURATION] [-- TERRAFORM_OPTIONS ]
      tf clean

DESCRIPTION
      init
           init the specified configuration in .tmp and setup the backend
           according to the current ENVIRONMENT

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

      -c | --configuration CONFIGURATION
            The name of the configuration to apply. It must be within the
            configuration directory in lib.git
            Can be set with CONFIGURATION environment variable

      -r | --revision GIT_REVISION
            The git revision to extract from lib.git
            Can be set with GIT_REVISION environment variable

            default: refs/heads/master

      -l | --lib-url LIB_URL
            Git modules repository url
            Can be set with LIB_URL environment variable

            default: git@git.corp.cloudwatt.com:pocwatt/terraform/lib.git

      -e | --environment ENVIRONMENT
            The environment (i.e DNS domain) we are targetting
            Can be set with ENVIRONMENT environment variable

            default: current git repo name

EXAMPLES

      $ tf apply -c base -r refs/head/master \\
          -m git@git.corp.cloudwatt.com:pocwatt/terraform/mylib.git -e client1

      $ CONFIGURATION=base tf init
EOF

}

function _tf_generic () {
  (
    cd "${TMP_DIR}/configurations/${CONFIGURATION}"
    terraform "$@"
  )
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
  _tf_generic init -upgrade=true
}

function _tf_clean () {
  rm -rf "${TMP_DIR}" &>/dev/null || true
}

function _tf_debug () {
  # let's display every parameter
  echo "ACTION: ${ACTION}" >&2
  echo "CONFIGURATION: ${CONFIGURATION}" >&2
  echo "GIT_REVISION: ${GIT_REVISION}" >&2
  echo "LIB_URL: ${LIB_URL}" >&2
  echo "ENVIRONMENT: ${ENVIRONMENT}" >&2
  echo "TMP_DIR: ${TMP_DIR}" >&2
  echo "TERRAFORM_OPTIONS: ${TERRAFORM_OPTIONS}" >&2
  terraform -v >&2
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
  DEBUG="${DEBUG:-0}"

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

}


_tf_parsing "$@"

if [[ ${DEBUG} -gt 0 ]]; then _tf_debug; fi

case ${ACTION} in
  clean | init)
    "_tf_${ACTION}"
  ;;
  apply | plan)
    _tf_init
  ;& # bash 4 - the execution flow continue, the next pattern is not checked and the block is executed
  show | destroy)
    # shellcheck disable=2086
    _tf_generic "${ACTION}" ${TERRAFORM_OPTIONS}
  ;;
  * )
    _tf_help;
    exit 1
  ;;
esac
