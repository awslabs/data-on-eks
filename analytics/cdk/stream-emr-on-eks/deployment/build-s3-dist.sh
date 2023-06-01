#!/bin/bash
#
# This script packages your project into a solution distributable that can be
# used as an input to the solution builder validation pipeline.
#
# Important notes and prereq's:
#   1. The initialize-repo.sh script must have been run in order for this script to
#      function properly.
#   2. This script should be run from the repo's root folder.
#
# This script will perform the following tasks:
#   1. Remove any old dist files from previous runs.
#   2. Install dependencies for the cdk-solution-helper; responsible for
#      converting standard 'cdk synth' output into solution assets.
#   3. Build and synthesize your CDK project.
#   4. Run the cdk-solution-helper on template outputs and organize
#      those outputs into the /global-s3-assets folder.
#   5. Organize source code artifacts into the /regional-s3-assets folder.
#   6. Remove any temporary files used for staging.
#
# Parameters:
#  - source-bucket-base-name: Name for the S3 bucket location where the template will source the Lambda
#    code from. The template will append '-[region_name]' to this bucket name.
#    For example: ./build-s3-dist.sh solutions v1.0.0
#    The template will then expect the source code to be located in the solutions-[region_name] bucket
#  - solution-name: name of the solution for consistency
#  - version-code: version of the package

# Important: CDK global version number
cdk_version===2.67.0

# Check to see if the required parameters have been provided:
if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ]; then
    echo "Please provide the base source bucket name, trademark approved solution name and version where the lambda code will eventually reside."
    echo "For example: ./build-s3-dist.sh solutions trademarked-solution-name v1.0.0 template-bucket-name"
    exit 1
fi

# Get reference for all important folders
template_dir="$PWD"
staging_dist_dir="$template_dir/staging"
app_code_dir="$template_dir/deployment/app_code"
template_dist_dir="$template_dir/deployment/global-s3-assets"
build_dist_dir="$template_dir/deployment/regional-s3-assets"

echo "------------------------------------------------------------------------------"
echo "[Init] Remove any old dist files from previous runs"
echo "------------------------------------------------------------------------------"

echo "rm -rf $template_dist_dir"
rm -rf $template_dist_dir
echo "mkdir -p $template_dist_dir"
mkdir -p $template_dist_dir
echo "rm -rf $build_dist_dir"
rm -rf $build_dist_dir
echo "mkdir -p $build_dist_dir"
mkdir -p $build_dist_dir
echo "rm -rf $staging_dist_dir"
rm -rf $staging_dist_dir
echo "mkdir -p $staging_dist_dir"
mkdir -p $staging_dist_dir

echo "------------------------------------------------------------------------------"
echo "[Init] Install dependencies for the cdk-solution-helper"
echo "------------------------------------------------------------------------------"

echo "cd $template_dir/deployment/cdk-solution-helper"
cd $template_dir/deployment/cdk-solution-helper
echo "npm install"
# npm audit fix --force
npm install

cd $template_dir
echo "pip3 install -r requirements.txt"
python3 -m venv .env
source .env/bin/activate
pip3 install --upgrade pip -r requirements.txt

echo "------------------------------------------------------------------------------"
echo "[Synth] CDK Project"
echo "------------------------------------------------------------------------------"

# # Install the global aws-cdk package
echo "npm install -g aws-cdk@$cdk_version"
# npm audit fix --force
npm install aws-cdk@$cdk_version

# Run 'cdk synth' to generate raw solution outputs
echo "cdk synth --output=$staging_dist_dir"
node_modules/aws-cdk/bin/cdk synth --output=$staging_dist_dir

# Remove unnecessary output files
echo "cd $staging_dist_dir"
cd $staging_dist_dir
echo "rm tree.json manifest.json cdk.out"
rm tree.json manifest.json cdk.out

echo "------------------------------------------------------------------------------"
echo "[Packing] Template artifacts"
echo "------------------------------------------------------------------------------"

# Move outputs from staging to template_dist_dir
echo "Move outputs from staging to template_dist_dir"
mv $staging_dist_dir/*.json $template_dist_dir/

# Rename all *.template.json files to *.template
echo "Rename all *.template.json to *.template"
echo "copy templates and rename"
for f in $template_dist_dir/*.template.json; do
    mv -- "$f" "${f%.template.json}.template"
done

# Run the helper to clean-up the templates and remove unnecessary CDK elements
echo "Run the helper to clean-up the templates and remove unnecessary CDK elements"
echo "node $template_dir/deployment/cdk-solution-helper/index"
node $template_dir/deployment/cdk-solution-helper/index
if [ "$?" = "1" ]; then
	echo "(cdk-solution-helper) ERROR: there is likely output above." 1>&2
	exit 1
fi

# Find and replace bucket_name, solution_name, and version
echo "Find and replace bucket_name, solution_name, and version"
cd $template_dist_dir
echo "Updating code source bucket in template with $1"
replace="s/%%BUCKET_NAME%%/$1/g"
echo "sed -i '' -e $replace $template_dist_dir/*.template"
sed -i '' -e $replace $template_dist_dir/*.template
replace="s/%%SOLUTION_NAME%%/$2/g"
echo "sed -i '' -e $replace $template_dist_dir/*.template"
sed -i '' -e $replace $template_dist_dir/*.template
replace="s/%%VERSION%%/$3/g"
echo "sed -i '' -e $replace $template_dist_dir/*.template"
sed -i '' -e $replace $template_dist_dir/*.template

# Put Global and Regional code files in a single bucket if the 4th parameter doesn't exist
if [ -z "$4" ]; then
    replace="s/%%TEMPLATE_OUTPUT_BUCKET%%/$1"-"${AWS_REGION}/g"
else
    replace="s/%%TEMPLATE_OUTPUT_BUCKET%%/$4/g"    
fi

echo "sed -i '' -e $replace $template_dist_dir/*.template"
sed -i '' -e $replace $template_dist_dir/*.template

rm $template_dist_dir/*.json

echo "------------------------------------------------------------------------------"
echo "[Packing] Source code artifacts"
echo "------------------------------------------------------------------------------"

# General cleanup of node_modules and package-lock.json files
echo "find $staging_dist_dir -iname "node_modules" -type d -exec rm -rf "{}" \; 2> /dev/null"
find $staging_dist_dir -iname "node_modules" -type d -exec rm -rf "{}" \; 2> /dev/null
echo "find $staging_dist_dir -iname "package-lock.json" -type f -exec rm -f "{}" \; 2> /dev/null"
find $staging_dist_dir -iname "package-lock.json" -type f -exec rm -f "{}" \; 2> /dev/null

# ... For each asset.* source code artifact in the temporary /staging folder...
cd $staging_dist_dir
for d in `find . -mindepth 1 -maxdepth 1 -type d`; do

    # Rename the artifact, removing the period for handler compatibility
    pfname="$(basename -- $d)"
    fname="$(echo $pfname | sed -e 's/\.//g')"
    echo "zip -r $fname.zip $fname"
    mv $d $fname
    cd $staging_dist_dir/$fname

    # Build the artifcats
    if ls *.py 1> /dev/null 2>&1; then
        echo "===================================="
        echo "This is Python runtime"
        echo "===================================="
        venv_folder=".venv-prod"
        rm -fr .venv-test
        rm -fr .venv-prod
        echo "Initiating virtual environment"
        python3 -m venv $venv_folder
        source $venv_folder/bin/activate
        pip3 install --upgrade pip -q $template_dir --target $venv_folder/lib/python3.*/site-packages
        echo "package python artifact"
        cd $venv_folder/lib/python3.*/site-packages
        zip -qr9 $staging_dist_dir/$fname.zip . -x "aws_cdk/*"
        echo "zip -r $staging_dist_dir/$fname"
        cd $staging_dist_dir/$fname
        rm -rf $venv_folder
        zip -grq $staging_dist_dir/$fname.zip .
       
    elif ls *.js 1> /dev/null 2>&1; then
        echo "===================================="
        echo "This is Node runtime"
        echo "===================================="
        echo "Clean and rebuild artifacts"
        # npm audit fix --force
        npm run
        npm ci
        echo "copy package.json and package-lock.json files"
        cp -rf $template_dir/deployment/cdk-solution-helper/*.json .
        if [ "$?" = "1" ]; then
	        echo "ERROR: Seems like package-lock.json does not exists or is out of sync with package.josn. Trying npm install instead" 1>&2
            npm install
        fi
        # Zip the artifact
        echo "zip -r $staging_dist_dir/$fname"
        zip -qr9 $staging_dist_dir/$fname.zip .
    else
        # Zip the artifact
        echo "zip -r $staging_dist_dir/$fname"
        zip -rq $staging_dist_dir/$fname.zip .
    fi    

    cd $staging_dist_dir
    # Copy the zipped artifact from /staging to /regional-s3-assets
    echo "cp $fname.zip $build_dist_dir"
    mv $fname.zip $build_dist_dir

    # Remove the old, unzipped artifact from /staging
    echo "rm -rf $fname"
    rm -rf $fname

    # ... repeat until all source code artifacts are zipped and placed in the
    # ... /regional-s3-assets folder

done

echo "------------------------------------------------------------------------------"
echo "[Move] the zip files from staging to regional-s3-assets folder"
echo "------------------------------------------------------------------------------"
for d in `find . -mindepth 1 -maxdepth 1`; do
    pfname="$(basename -- $d)"
    fname="$(echo $pfname | sed -e 's/asset./asset/g')"
    mv $d $build_dist_dir/$fname
done    

echo "------------------------------------------------------------------------------"
echo "[Cleanup] Remove temporary files"
echo "------------------------------------------------------------------------------"

# Delete the temporary /staging folder
echo "rm -rf $staging_dist_dir"
rm -rf $staging_dist_dir

