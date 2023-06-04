# // Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# // SPDX-License-Identifier: License :: OSI Approved :: MIT No Attribution License (MIT-0)
import yaml
import urllib.request as request
import os.path as path
import sys

def load_yaml_remotely(url, multi_resource=False):
    try:
        file_to_parse = request.urlopen(url)
        if multi_resource:
            yaml_data = list(yaml.full_load_all(file_to_parse))
        else:
            yaml_data = yaml.full_load(file_to_parse) 
        # print(yaml_data)  
    except:
        print("Cannot read yaml config file {}, check formatting."
                "".format(file_to_parse))
        sys.exit(1)
        
    return yaml_data 

def load_yaml_local(yaml_file, multi_resource=False):

    file_to_parse=path.join(path.dirname(__file__), yaml_file)
    if not path.exists(file_to_parse):
        print("The file {} does not exist"
            "".format(file_to_parse))
        sys.exit(1)

    try:
        with open(file_to_parse, 'r') as yaml_stream:
            if multi_resource:
                yaml_data = list(yaml.full_load_all(yaml_stream))
            else:
                yaml_data = yaml.full_load(yaml_stream) 
            # print(yaml_data)    
    except:
        print("Cannot read yaml config file {}, check formatting."
                "".format(file_to_parse))
        sys.exit(1)
        
    return yaml_data 

def load_yaml_replace_var_remotely(url, fields, multi_resource=False):
    try:
        with request.urlopen(url) as f:
            file_to_replace = f.read().decode('utf-8')
            for searchwrd,replwrd in fields.items():
                file_to_replace = file_to_replace.replace(searchwrd, replwrd)

        if multi_resource:
            yaml_data = list(yaml.full_load_all(file_to_replace))
        else:
            yaml_data = yaml.full_load(file_to_replace) 
        # print(yaml_data)
    except request.URLError as e:
        print(e.reason)
        sys.exit(1)

    return yaml_data


def load_yaml_replace_var_local(yaml_file, fields, multi_resource=False, write_output=False):

    file_to_replace=path.join(path.dirname(__file__), yaml_file)
    if not path.exists(file_to_replace):
        print("The file {} does not exist"
            "".format(file_to_replace))
        sys.exit(1)

    try:
        with open(file_to_replace, 'r') as f:
            filedata = f.read()

            for searchwrd, replwrd in fields.items():
                filedata = filedata.replace(searchwrd, replwrd)
            if multi_resource:
                yaml_data = list(yaml.full_load_all(filedata))
            else:
                yaml_data = yaml.full_load(filedata) 
        if write_output:
            with open(file_to_replace, "w") as f:
                yaml.dump(yaml_data, f, default_flow_style=False, allow_unicode = True, sort_keys=False)
    
        # print(yaml_data)
    except request.URLError as e:
        print(e.reason)
        sys.exit(1)

    return yaml_data
