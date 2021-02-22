#!/bin/bash

FILENAMEPART1="name"
FILENAMEPART2="_COMPLETE_Delta.csv"
RED='\033[0;31m'
GREEN='\033[0;32m'
ORANGE='\033[0;33m'
YELLOW='\033[1;33m'
NC='\033[0m'
#This is as per the profile configured in .aws/config
PROFILE="some profile name" 

ENV="prod"

#Debugging script
#set -x

#REPORTDATE="$(date -u "+%Y-%m-%d")"
REPORTDATE="2020-11-14"

#Report date for Filename pattern
RDFNP="$(date -j -f "%F" "$REPORTDATE"  "+%Y%m%d")"

#Report date for log stream pattern
RDLSP="$(date -j -f "%F" "$REPORTDATE"  "+%Y/%m/%d")"

UPDATEFNP1=${FILENAMEPART1}${RDFNP}

#When using this adhoc file attribute, change Record calculation in getFileAttributes function
#ADHOCFILE="adhocfilename.csv"



function getLog {

  STATUS=""
  echo -e "\n Getting log for lambda ${1} ------------------------------------------\n"

  aws logs filter-log-events --log-group-name /aws/lambda/${ENV}-"${1}" --log-stream-name-prefix "$RDLSP" --start-time "${FAEpochms}" --filter-pattern FATAL --profile ${PROFILE} --region eu-west-1 > "${RDFNP}""${1}"FATAL.json
  
  if [ "$(jq ".events|length" "${RDFNP}""${1}"FATAL.json)" -gt 0   ] ;then
    STATUS="${RED} ${ENV} ${1} status :FAIL${NC}"
    echo -e "${STATUS}"
    jq ".events[].message" "${RDFNP}""${1}"FATAL.json|awk -F'\"' '{print $3}'|awk -F':' '{print $1}' |sort|uniq -c
  fi

  aws logs filter-log-events --log-group-name /aws/lambda/${ENV}-"${1}" --log-stream-name-prefix "$RDLSP" --start-time "${FAEpochms}" --filter-pattern ERROR --profile ${PROFILE} --region eu-west-1 > "${RDFNP}""${1}"ERROR.json
  
  if [ "$(jq ".events|length" "${RDFNP}""${1}"ERROR.json)" -gt 0   ] ;then
    STATUS="${ORANGE} ${ENV} ${1} status: Successful with Errors${NC}"
    echo -e "${STATUS}"
    jq ".events[].message" "${RDFNP}""${1}"ERROR.json|awk -F'\"' '{print $3}'|awk -F':' '{print $1}' |sort|uniq -c
    
  fi

  aws logs filter-log-events --log-group-name /aws/lambda/${ENV}-"${1}" --log-stream-name-prefix "$RDLSP" --start-time "${FAEpochms}" --filter-pattern WARN --profile ${PROFILE} --region eu-west-1 > "${RDFNP}""${1}"WARN.json
  
  if [ "$(jq ".events|length" "${RDFNP}""${1}"WARN.json)" -gt 0   ];then
    STATUS="${YELLOW} ${ENV} ${1} status: Successful with Warnings${NC}"
    echo -e "${STATUS}"
    jq ".events[].message" "${RDFNP}""${1}"WARN.json|awk -F'\"' '{print $3}'|awk -F':' '{print $1}' |sort|uniq -c
    
  fi

  aws logs filter-log-events --log-group-name /aws/lambda/${ENV}-"${1}" --log-stream-name-prefix "$RDLSP" --start-time "${FAEpochms}" --filter-pattern "unexpected EOF" --profile ${PROFILE} --region eu-west-1 > "${RDFNP}""${1}"LambdaExit.json
  
  if [ "$(jq ".events|length" "${RDFNP}""${1}"LambdaExit.json)" -gt 0   ];then
    STATUS="${YELLOW} ${ENV} ${1} status: Lambda exitted in between${NC}"
    echo -e "${STATUS}"
    
    
  fi

  aws logs filter-log-events --log-group-name /aws/lambda/${ENV}-"${1}" --log-stream-name-prefix "$RDLSP" --start-time "${FAEpochms}" --filter-pattern "runtime error" --profile ${PROFILE} --region eu-west-1 > "${RDFNP}""${1}"RuntimeError.json
  
  if [ "$(jq ".events|length" "${RDFNP}""${1}"RuntimeError.json)" -gt 0   ];then
    STATUS="${RED} ${ENV} ${1} status: Runtime errors ${NC}"
    echo -e "${STATUS}"
    
    
  fi

  aws logs filter-log-events --log-group-name /aws/lambda/${ENV}-"${1}" --log-stream-name-prefix "$RDLSP" --start-time "${FAEpochms}" --filter-pattern "START RequestId" --profile ${PROFILE} --region eu-west-1 > "${RDFNP}""${1}"NoofInvocations.json
  INVOCCOUNT="$(jq ".events|length" "${RDFNP}""${1}"NoofInvocations.json)"
  if [ $INVOCCOUNT -gt 0   ];then
    MSG="${GREEN} ${ENV} ${1} Number of Invocations: ${INVOCCOUNT} ${NC}"
    echo -e "${MSG}"
    
    
  fi

  

  if [ "$STATUS" = "" ]; then
    STATUS="${GREEN} ${ENV} ${1} status: Successful${NC}"
    echo -e "${STATUS}"
  fi
  
  
  


}

function getCompletionMetricsFromLogs {
  
  PCEpoch="$(aws logs filter-log-events --log-group-name /aws/lambda/${ENV}-supervisor_name --log-stream-name-prefix "$RDLSP" --filter-pattern 'REPORT RequestId' --start-time "${FAEpochms}" --profile ${PROFILE} --region eu-west-1 | jq ".events[]" | jq .timestamp| sort |tail -n 1)"
  #Convert millisecond to second
  PCEpoch="$((PCEpoch/1000))"
  PCFormat="$(date -r "${PCEpoch}" "+%F %T %Z")"
  echo -e "Processing completed at: $PCFormat"

  secs=$(( (PCEpoch-FAEpoch) ))
  ET="$(printf '%02dh:%02dm:%02ds\n' $((secs/3600)) $((secs%3600/60)) $((secs%60)))"
  echo -e "Total time taken to process the run $ET "


  RS="$(aws logs filter-log-events --log-group-name /aws/lambda/${ENV}-worker_name --log-stream-name-prefix "$RDLSP" --start-time "${FAEpochms}" --filter-pattern 'Total marked' --no-interleaved --profile ${PROFILE} --region eu-west-1 | jq ".events[]" | jq .message | awk -F':' '{print $7}' | awk -F'\' '{print $1}' |awk '{n +=$1}; END{print n}')"
  echo -e "Number of records sent to name: $RS"
}

function getFileAttributes {
  RECORD1="$(aws s3 ls s3://${ENV}-name --recursive --profile ${PROFILE} --region eu-west-1 | grep "$UPDATEFNP1" | grep $FILENAMEPART2 )"
  
  FA="$(echo "${RECORD1}"| awk -F' ' '{print $1,$2}')"
  
  FAEpoch="$(date -j -f "%F %T" "${FA}" +"%s")"

  FAZone="$(date -r "${FAEpoch}" "+%F %T %Z")"
  #Epoch in ms
  FAEpochms="${FAEpoch}000"
  FS="$(echo "${RECORD1}"| awk -F' ' '{print $3}'|numfmt --to=iec-i)"
  echo -e "File arrived: $FAZone"
  echo -e "File size: $FS "

  

}

function getRecordInfoFromFile {
  if [ "$RECORD1" = "" ]; then
    RECORD1="$(aws s3 ls s3://${ENV}-name --recursive --profile ${PROFILE} --region eu-west-1 | grep "$UPDATEFNP1" | grep $FILENAMEPART2 )"
  fi
  FN="$(echo "${RECORD1}"| awk -F' ' '{print $4}')"
  aws s3 cp --profile ${PROFILE} --region eu-west-1 s3://${ENV}-name/${FN} ${FN}

  echo -e "Number of Lines in the file ${FN}"
  wc -l ${FN}
}

function getRecordsStatsFromLogs {
  #Number of records in file
  NRF="$(aws logs filter-log-events --log-group-name /aws/lambda/${ENV}-name --log-stream-name-prefix "$RDLSP" --start-time "${FAEpochms}" --filter-pattern 'Total records seen' --no-interleaved --profile ${PROFILE} --region eu-west-1| jq ".events[]" | jq .message | awk -F':' '{print $7}' | awk -F'\' '{print $1}'|awk '{n +=$1}; END{print n}')" 
  echo -e "Number of records in the file: $NRF"

  #Malformed records
  MR="$(aws logs filter-log-events --log-group-name /aws/lambda/${ENV}-name --log-stream-name-prefix "$RDLSP" --start-time "${FAEpochms}" --filter-pattern 'Malformed' --no-interleaved --profile ${PROFILE} --region eu-west-1| jq ".events[]" | jq .message | awk -F':' '{print $7}' | awk -F'\' '{print $1}'|awk '{n +=$1}; END{print n}')"
  echo -e "Number of malformed records in the file: $MR"
}


function getRecordsInsertedDB2FromLogs {
  #Number of records inserted in to DB2: 1597
  RI="$(aws logs filter-log-events --log-group-name /aws/lambda/${ENV}-supervisor_name --log-stream-name-prefix "$RDLSP" --start-time "${FAEpochms}" --filter-pattern 'Total IDs selected' --no-interleaved --profile ${PROFILE} --region eu-west-1| jq ".events[]" | jq .message | awk -F':' '{print $7}' | awk -F'\' '{print $1}'|awk '{n +=$1}; END{print n}')"
  echo -e "Number of records inserted in to DB2: $RI"
}


echo -e "Calling Go to get db values"
#./Gotool/Gotool "${PROFILE}" "${ENV}" "${REPORTDATE}"
echo -e "Done"
#Stage1

cd ./results || exit

echo -e "-----------------STAGE1 Begins--------------------------"
getFileAttributes

getLog lambda1

getLog lambda2

getLog lambda3

getRecordsStatsFromLogs


echo -e "-----------------STAGE2 Begins--------------------------"
#Stage 2

getLog lambda4

getLog lambda5

getRecordsInsertedDB2FromLogs


echo -e "-----------------STAGE3 Begins--------------------------"
#Stage 3
getLog lambda6

getLog lambda7

getCompletionMetricsFromLogs



