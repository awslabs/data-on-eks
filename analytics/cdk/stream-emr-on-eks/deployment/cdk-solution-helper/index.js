#!/usr/bin/env node
// Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
// SPDX-License-Identifier: License :: OSI Approved :: MIT No Attribution License (MIT-0)
// Imports
const fs = require('fs');

// Paths
var currentPath = process.cwd();
const global_s3_assets = currentPath+'/../deployment/global-s3-assets';
const solution_name='emr-stream-demo';

function setParameter(template) {
    const parameters = (template.Parameters) ? template.Parameters : {};
    const assetParameters = Object.keys(parameters).filter(function(key) {
      return key.includes('BootstrapVersion');
    });
    assetParameters.forEach(function(a) {
        template.Parameters[a] = undefined;
    });
    const rules = (template.Rules) ? template.Rules : {};
    const rule = Object.keys(rules).filter(function(key) {
      return key.includes('CheckBootstrapVersion');
    });
    rule.forEach(function(a) {
      template.Rules[a] = undefined;
  })
}
function assetRef(s3BucketRef) {
  // Get S3 bucket key references from assets file
    const raw_meta = fs.readFileSync(`${global_s3_assets}/${solution_name}.assets.json`);
    let template = JSON.parse(raw_meta);
    const metadata = (template.files[s3BucketRef]) ? template.files[s3BucketRef] : {};
    var assetPath = metadata.source.path.replace('.json','');
    return assetPath;
}

// For each template in global_s3_assets ...
fs.readdirSync(global_s3_assets).forEach(file => {
  if ( file != `${solution_name}.assets.json`) {
    // Import and parse template file
    const raw_template = fs.readFileSync(`${global_s3_assets}/${file}`);
    let template = JSON.parse(raw_template);

    //1. Clean-up parameters section
    setParameter(template);

    const resources = (template.Resources) ? template.Resources : {};
    //3. Clean-up Account ID and region to enable cross account deployment
    const rsrctype=[
      "AWS::Lambda::Function",
      "AWS::Lambda::LayerVersion",
      "Custom::CDKBucketDeployment",
      "AWS::CloudFormation::Stack",
      "AWS::CloudFront::Distribution"
    ]
    const focusTemplate = Object.keys(resources).filter(function(key) {
      return (resources[key].Type.indexOf(rsrctype) < 0)
    });
    focusTemplate.forEach(function(f) {
        const fn = template.Resources[f];
        if (fn.Properties.hasOwnProperty('Code') && fn.Properties.Code.hasOwnProperty('S3Bucket')) {
          // Set Lambda::Function S3 reference to regional folder
          if (! String(fn.Properties.Code.S3Bucket.Ref).startsWith('appcode')){
            fn.Properties.Code.S3Key = `%%SOLUTION_NAME%%/%%VERSION%%/asset`+fn.Properties.Code.S3Key;
            fn.Properties.Code.S3Bucket = {'Fn::Sub': '%%BUCKET_NAME%%-${AWS::Region}'};
          }
        }
        else if (fn.Properties.hasOwnProperty('Content') && fn.Properties.Content.hasOwnProperty('S3Bucket')) {
          // Set Lambda::LayerVersion S3 bucket reference
          fn.Properties.Content.S3Key = `%%SOLUTION_NAME%%/%%VERSION%%/asset`+fn.Properties.Content.S3Key;
          fn.Properties.Content.S3Bucket = {'Fn::Sub': '%%BUCKET_NAME%%-${AWS::Region}'};
        }
        else if (fn.Properties.hasOwnProperty('SourceBucketNames')) {
          // Set CDKBucketDeployment S3 bucket reference
          fn.Properties.SourceObjectKeys = [`%%SOLUTION_NAME%%/%%VERSION%%/asset`+fn.Properties.SourceObjectKeys[0]];
          fn.Properties.SourceBucketNames = [{'Fn::Sub': '%%BUCKET_NAME%%-${AWS::Region}'}];
        }
        else if (fn.Properties.hasOwnProperty('PolicyName') && fn.Properties.PolicyName.includes('CustomCDKBucketDeployment')) {
          // Set CDKBucketDeployment S3 bucket Policy reference
          fn.Properties.PolicyDocument.Statement.forEach(function(sub,i) {
            if (typeof(sub.Resource[i]) === 'object') {
              sub.Resource.forEach(function(resource){
                var arrayKey = Object.keys(resource);
                if (typeof(resource[arrayKey][1]) === 'object') {
                  resource[arrayKey][1].filter(function(s){
                      if (s.hasOwnProperty('Ref')) {
                        fn.Properties.PolicyDocument.Statement[i].Resource = [
                        {"Fn::Join": ["",["arn:",{"Ref": "AWS::Partition"},":s3:::%%BUCKET_NAME%%-",{"Ref": "AWS::Region"}]]},
                        {"Fn::Join": ["",["arn:",{"Ref": "AWS::Partition"},":s3:::%%BUCKET_NAME%%-",{"Ref": "AWS::Region"},"/*"]]}]}})}})}});
        }
        // Set NestedStack S3 bucket reference
        else if (fn.Properties.hasOwnProperty('TemplateURL')) {
          var key=fn.Properties.TemplateURL['Fn::Join'][1][6].replace('.json','').replace('/','');
          var assetPath = assetRef(key);
          fn.Properties.TemplateURL = {
            "Fn::Join": ["",
              [
                "https://s3.",
                {
                  "Ref": "AWS::URLSuffix"
                },
                "/",
                `%%TEMPLATE_OUTPUT_BUCKET%%/%%SOLUTION_NAME%%/%%VERSION%%/${assetPath}`
              ]]
          };
        }
        // Set CloudFront logging bucket
        else if (fn.Properties.hasOwnProperty('DistributionConfig')){
          fn.Properties.DistributionConfig.Logging.Bucket= {
            "Fn::Join": ["",[fn.Properties.DistributionConfig.Logging.Bucket['Fn::Join'][1][0],
            ".s3.",{"Ref": "AWS::Region"},".",{"Ref": "AWS::URLSuffix"}]]
          }
        }
    });

    //6. Output modified template file
    const output_template = JSON.stringify(template, null, 2);
    fs.writeFileSync(`${global_s3_assets}/${file}`, output_template);
  }
});
