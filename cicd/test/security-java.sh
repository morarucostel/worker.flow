#!/bin/bash

#( printf '\n'; printf '%.0s-' {1..30}; printf ' Security Test - Java '; printf '%.0s-' {1..30}; printf '\n\n' )

COMPONENT_NAME=${1}
VERSION_NAME=${2}
ART_URL=${3}
ART_REPO_USER=${4}
ART_REPO_PASSWORD=${5}
ASOC_APP_ID=${6}
ASOC_LOGIN_KEY_ID=${7}
ASOC_LOGIN_SECRET=${8}
ASOC_CLIENT_CLI=${9}
ASOC_JAVA_RUNTIME=${10}

# Download ASoC CLI
echo "SAClientUtil File: $ART_URL/$ASOC_CLIENT_CLI"
echo "Creds: $ART_REPO_USER:$ART_REPO_PASSWORD"
curl --noproxy "$NO_PROXY" --insecure -u $ART_REPO_USER:$ART_REPO_PASSWORD "$ART_URL/$ASOC_CLIENT_CLI" -o SAClientUtil.zip

# Unzip ASoC CLI
unzip SAClientUtil.zip
rm -f SAClientUtil.zip
SAC_DIR=`ls -d SAClientUtil*`
echo "SAC_DIR=$SAC_DIR"
mv $SAC_DIR SAClientUtil
mv SAClientUtil ..

echo "-Xmx4g" | tee -a /data/SAClientUtil/config/cli.config
cat /data/SAClientUtil/config/cli.config

# Compile Source
if [ "$HTTP_PROXY" != "" ]; then
    # Swap , for |
    MAVEN_PROXY_IGNORE=`echo "$NO_PROXY" | sed -e 's/ //g' -e 's/\"\,\"/\|/g' -e 's/\,\"/\|/g' -e 's/\"$//' -e 's/\,/\|/g'`
    export MAVEN_OPTS="-Dhttp.proxyHost=$PROXY_HOST -Dhttp.proxyPort=$PROXY_PORT -Dhttp.nonProxyHosts='$MAVEN_PROXY_IGNORE' -Dhttps.proxyHost=$PROXY_HOST -Dhttps.proxyPort=$PROXY_PORT -Dhttps.nonProxyHosts='$MAVEN_PROXY_IGNORE'"
fi
echo "MAVEN_OPTS=$MAVEN_OPTS"
mvn clean package install -DskipTests=true -Dmaven.wagon.http.ssl.insecure=true -Dmaven.wagon.http.ssl.allowall=true -Dmaven.wagon.http.ssl.ignore.validity.dates=true

export JAVA_HOME=/usr/lib/jvm/java-11-openjdk
export PATH="/usr/lib/jvm/java-11-openjdk/bin:${PATH}"

export ASOC_PATH=/data/SAClientUtil
export PATH="${ASOC_PATH}:${ASOC_PATH}/bin:${PATH}"

export LD_LIBRARY_PATH=/usr/local/lib:/usr/glibc-compat/lib:/opt/libs/lib:/usr/lib:/lib:/data/SAClientUtil/bin
echo "LD_LIBRARY_PATH=$LD_LIBRARY_PATH"
export DYLD_LIBRARY_PATH=/usr/local/lib:/usr/glibc-compat/lib:/opt/libs/lib:/usr/lib:/lib:/data/SAClientUtil/bin
echo "DYLD_LIBRARY_PATH=$DYLD_LIBRARY_PATH"

# echo "-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-"
# ldd /data/SAClientUtil/bin/StaticAnalyzer
# echo "-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-"

# Generate IRX file
export APPSCAN_OPTS="-Dhttp.proxyHost=$PROXY_HOST -Dhttp.proxyPort=$PROXY_PORT -Dhttps.proxyHost=$PROXY_HOST -Dhttps.proxyPort=$PROXY_PORT"
echo "APPSCAN_OPTS=$APPSCAN_OPTS"
/data/SAClientUtil/bin/appscan.sh prepare -v -X -n ${COMPONENT_NAME}_${VERSION_NAME}.irx

ls -al

curl -T glen.test.java_0.0.41-8.failed "https://tools.boomerangplatform.net/artifactory/boomerang/software/asoc/glen.test.java_0.0.30-5.failed" --insecure -u $ART_REPO_USER:$ART_REPO_PASSWORD
curl -T glen.test.java_0.0.41-8_logs.zip "https://tools.boomerangplatform.net/artifactory/boomerang/software/asoc/glen.test.java_0.0.30-5_logs.zip" --insecure -u $ART_REPO_USER:$ART_REPO_PASSWORD

# Sleep 5 minutes for debugging
sleep 300

# echo "========================================================================================="
# cat appscan-config.xml
# echo "========================================================================================="

cat /data/SAClientUtil/logs/client.log

if [ ! -f "${COMPONENT_NAME}_${VERSION_NAME}.irx" ]; then
  exit 128
fi

# Start Static Analyzer ASoC Scan
echo "ASoC App ID: $ASOC_APP_ID"
echo "ASoC Login Key ID: $ASOC_LOGIN_KEY_ID"
echo "ASoC Login Secret ID: $ASOC_LOGIN_SECRET"

/data/SAClientUtil/bin/appscan.sh api_login -u $ASOC_LOGIN_KEY_ID -P $ASOC_LOGIN_SECRET
ASOC_SCAN_ID=$(/data/SAClientUtil/bin/appscan.sh queue_analysis -a $ASOC_APP_ID -f ${COMPONENT_NAME}_${VERSION_NAME}.irx -n ${COMPONENT_NAME}_${VERSION_NAME} | tail -n 1)
echo "ASoC Scan ID: $ASOC_SCAN_ID"

if [ -z "$ASOC_SCAN_ID" ]; then
  exit 129
fi

START_SCAN=`date +%s`
RUN_SCAN=true
while [ "$(/data/SAClientUtil/bin/appscan.sh status -i $ASOC_SCAN_ID)" != "Ready" ] && [ "$RUN_SCAN" == "true" ]; do
  NOW=`date +%s`
  DIFF=`expr $NOW - $START_SCAN`
  if [ $DIFF -gt 600 ]; then
    echo "Timed out waiting for ASoC job to complete [$DIFF/600]"
    RUN_SCAN=false
  else
    echo "ASoC job execution not completed ... waiting 15 seconds they retrying [$DIFF/600]"
    sleep 15
  fi
done

if [ "$RUN_SCAN" == "false" ]; then
  exit 130
fi

#Get ASoC execution summary
/data/SAClientUtil/bin/appscan.sh info -i $ASOC_SCAN_ID -json >> ASOC_Summary.json

# Download ASoC report
/data/SAClientUtil/bin/appscan.sh get_result -d ASOC_SCAN_RESULTS_${COMPONENT_NAME}_${VERSION_NAME}.html -i $ASOC_SCAN_ID

cat ASOC_SCAN_RESULTS_${COMPONENT_NAME}_${VERSION_NAME}.html

# Upload Scan Results
#ASOC_SCAN_RESULTS_$COMPONENT_NAME_$VERSION_NAME.html
