#!/bin/bash
if [ -z "$1" ];then
   echo "Usage Error:  build_release.sh <VersionNumber>"
   exit 1;
fi
echo "cleaning up previous version"
rm -rf releases/simple-data-generator

echo "building release version $1"
mkdir releases/simple-data-generator

echo "Adding runme scripts"
cp runme* releases/simple-data-generator

echo "Adding build_keystore.bash"
cp build_keystore.bash releases/simple-data-generator

echo "Building JAR"
gradle clean; gradle build fatJar

echo "Adding Elastic APM JavaAgent Libraries"
cp -ir apm_lib releases/simple-data-generator/.

echo "Adding Workload Example configs"
cp -ir examples releases/simple-data-generator/.

echo "Adding simple-data-generator jar"
cp build/libs/simple-*jar releases/simple-data-generator/simple-data-generator-$1.jar

echo "Creating Release TAR"
tar cf releases/simple-data-generator-$1.tar  releases/simple-data-generator

echo "Compressing Release TAR"
gzip -9 releases/simple-data-generator-$1.tar